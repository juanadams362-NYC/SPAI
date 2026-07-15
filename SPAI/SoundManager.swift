//
//  SoundManager.swift
//  SPAI
//
//  Created by Juan Adams on 6/24/26.
//

import AVFoundation

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ name: String, ext: String = "mp3") {
        if let player = players[name] {
            player.currentTime = 0
            player.play()
            return
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[SoundManager] couldn't find \(name).\(ext) in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[name] = player
            player.play()
        } catch {
            print("[SoundManager] failed to load \(name).\(ext): \(error)")
        }
    }

    func playContaminationAlert() {
        play("error_fx", ext: "mp3")
    }
}
