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
