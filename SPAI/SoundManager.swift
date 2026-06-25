//
//  SoundManager.swift
//  SPAI
//
//  Created by Juan Adams on 6/24/26.
//


//
//  SoundManager.swift
//  SPAI
//

import AVFoundation

@MainActor
final class SoundManager {
    /// Shared instance — one player, reused app-wide.
    static let shared = SoundManager()

    /// Cached players keyed by file name, so each sound loads from disk once.
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        // Make sure our sounds play even if the device is on silent / mixes
        // politely with other audio. Failing this isn't fatal — the sound
        // just might not play in some states — so we don't crash on it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Play a bundled sound by file name + extension (e.g. "error_fx", "mp3").
    /// Loads and caches the player on first use, then just replays after that.
    func play(_ name: String, ext: String = "mp3") {
        if let player = players[name] {
            player.currentTime = 0   // rewind so rapid re-triggers still sound
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

    /// Convenience for the contamination alert specifically.
    func playContaminationAlert() {
        play("error_fx", ext: "mp3")
    }
}
