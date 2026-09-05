//
//  SpeechManager.swift
//  SPAI
//
//  Created by Juan Adams on 7/23/26.
//

import AVFoundation
import RealityKit
import Speech
import SwiftUI

@MainActor
@Observable
final class SpeechManager {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()
    /// Dedicated synthesizer for offline buffer rendering, kept separate from `synthesizer` so
    /// spatial rendering never fights the flat-fallback speak path for playback state.
    private let renderSynthesizer = AVSpeechSynthesizer()

    /// RealityKit entity guided-step narration is spatialized from — set by ImmersiveView to the
    /// guided-step panel's attachment entity so instructions audibly come from its direction.
    var guidedAnchor: Entity?
    private var playbackController: AudioPlaybackController?
    private var speechToken = 0

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "speakSteps") }
        set { UserDefaults.standard.set(newValue, forKey: "speakSteps") }
    }

    private init() {}

    private static let preferredVoice: AVSpeechSynthesisVoice? = bestEnglishVoice()

        /// Speaks `text` spatially from `anchor` (or `guidedAnchor` if omitted). Falls back to
        /// flat, non-positional speech if no anchor is available yet.
        func speak(_ text: String, force: Bool = false, anchor: Entity? = nil) {
            guard isEnabled || force else { return }
            stop()
            speechToken += 1
            let token = speechToken

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.preferredVoice
            utterance.rate = 0.46
            utterance.pitchMultiplier = 0.98
            utterance.volume = 1.0
            utterance.preUtteranceDelay = 0.1

            guard let target = anchor ?? guidedAnchor else {
                synthesizer.speak(utterance)
                return
            }

            Task {
                do {
                    let fileURL = try await renderToFile(utterance)
                    let resource = try AudioFileResource.load(contentsOf: fileURL, configuration: .init(loadingStrategy: .preload, shouldLoop: false))
                    guard self.speechToken == token else { return }
                    self.playbackController = target.playAudio(resource)
                } catch {
                    print("[Speech] spatial render failed, falling back to flat audio: \(error)")
                    guard self.speechToken == token else { return }
                    self.synthesizer.speak(utterance)
                }
            }
        }

        /// Renders `utterance` to a temporary .caf file via the offline buffer callback API.
        private func renderToFile(_ utterance: AVSpeechUtterance) async throws -> URL {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
            return try await withCheckedThrowingContinuation { continuation in
                var audioFile: AVAudioFile?
                var didFinish = false
                renderSynthesizer.write(utterance) { buffer in
                    guard !didFinish else { return }
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                        didFinish = true
                        continuation.resume(throwing: SpeechManagerError.unsupportedBuffer)
                        return
                    }
                    if pcmBuffer.frameLength == 0 {
                        didFinish = true
                        continuation.resume(returning: tempURL)
                        return
                    }
                    do {
                        if audioFile == nil {
                            audioFile = try AVAudioFile(forWriting: tempURL, settings: pcmBuffer.format.settings)
                        }
                        try audioFile?.write(from: pcmBuffer)
                    } catch {
                        didFinish = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
            let english = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }

            if let premium = english.first(where: { $0.quality == .premium }) {
                print("[Speech] using premium voice: \(premium.name)")
                return premium
            }
            if let enhanced = english.first(where: { $0.quality == .enhanced }) {
                print("[Speech] using enhanced voice: \(enhanced.name)")
                return enhanced
            }
            print("[Speech] falling back to default voice")
            return AVSpeechSynthesisVoice(language: "en-US")
        }

    func stop() {
        speechToken += 1
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playbackController?.stop()
        playbackController = nil
    }
}

enum SpeechManagerError: Error {
    case unsupportedBuffer
}

@MainActor
@Observable
final class VoiceInputManager {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var transcript = ""
    var isListening = false
    var errorMessage: String?

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            Task { await startListening() }
        }
    }

    func startListening() async {
        guard !isListening else { return }
        errorMessage = nil

        guard await requestPermissions() else {
            errorMessage = "Microphone or speech recognition permission was not granted."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }
        // The input node only reports a valid (non-zero) format once the shared
        // session is actually configured for recording — without this, other
        // singletons (e.g. SoundManager's .ambient category) can leave the
        // session in a state where installTap below traps on a 0Hz/0-channel
        // format ("IsFormatSampleRateAndChannelCountValid").
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't configure the microphone."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = "Microphone isn't available right now."
            return
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Couldn't start microphone input."
            cleanupRecognition()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if error != nil {
                    self.errorMessage = "Speech recognition stopped."
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening || recognitionTask != nil || recognitionRequest != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        cleanupRecognition()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    private func cleanupRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    private func requestPermissions() async -> Bool {
        let speechAllowed = await requestSpeechPermission()
        let micAllowed = await requestMicrophonePermission()
        return speechAllowed && micAllowed
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}
