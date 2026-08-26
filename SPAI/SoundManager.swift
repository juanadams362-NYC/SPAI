//
//  SoundManager.swift
//  SPAI
//
//  Created by Juan Adams on 6/24/26.
//

import AVFoundation
import RealityKit

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]

    /// RealityKit entity the contamination alert is spatialized from — set by ImmersiveView
    /// to the detection panel's attachment entity so the alert audibly comes from its direction.
    var contaminationAnchor: Entity?
    private var contaminationResource: AudioFileResource?
    private var contaminationController: AudioPlaybackController?

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
        guard let anchor = contaminationAnchor else {
            play("error_fx", ext: "mp3")
            return
        }
        do {
            let resource = try contaminationResource ?? loadContaminationResource()
            contaminationResource = resource
            contaminationController = anchor.playAudio(resource)
        } catch {
            print("[SoundManager] spatial playback failed, falling back to flat audio: \(error)")
            play("error_fx", ext: "mp3")
        }
    }

    private func loadContaminationResource() throws -> AudioFileResource {
        guard let url = Bundle.main.url(forResource: "error_fx", withExtension: "mp3") else {
            throw SoundManagerError.missingResource
        }
        return try AudioFileResource.load(contentsOf: url, configuration: .init(loadingStrategy: .preload, shouldLoop: false))
    }
}

enum SoundManagerError: Error {
    case missingResource
}
