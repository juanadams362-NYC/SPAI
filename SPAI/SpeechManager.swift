//
//  SpeechManager.swift
//  SPAI
//
//  Created by Juan Adams on 7/23/26.
//

import AVFoundation
import SwiftUI

@MainActor
@Observable
final class SpeechManager {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "speakSteps") }
        set { UserDefaults.standard.set(newValue, forKey: "speakSteps") }
    }

    private init() {}

    private static let preferredVoice: AVSpeechSynthesisVoice? = bestEnglishVoice()

        func speak(_ text: String, force: Bool = false) {
            guard isEnabled || force else { return }
            stop()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.preferredVoice
            utterance.rate = 0.46
            utterance.pitchMultiplier = 0.98
            utterance.volume = 1.0
            utterance.preUtteranceDelay = 0.1
            synthesizer.speak(utterance)
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
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
