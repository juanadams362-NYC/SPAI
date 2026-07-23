//
//  SpeechManager.swift
//  SPAI
//

import AVFoundation
import SwiftUI

@MainActor
@Observable
final class SpeechManager {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    // Off by default so nothing starts talking on its own.
    // Settings flips it, and it sticks between launches.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "speakSteps") }
        set { UserDefaults.standard.set(newValue, forKey: "speakSteps") }
    }

    private init() {}

    // force = true is for safety alerts. A preference shouldn't be able
    // to silence a contamination warning.
    func speak(_ text: String, force: Bool = false) {
        guard isEnabled || force else { return }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}