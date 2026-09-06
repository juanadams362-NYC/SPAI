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

    /// Gain applied to the contamination alert, in decibels relative to the entity's normal
    /// level. This is the system's core safety signal and the tester barely registered it at
    /// the default level (0 dB), so it is deliberately pushed above ambient UI sound.
    ///
    /// error_fx.mp3 peaks at -4.6 dBFS and averages -19.7 dBFS RMS, so most of the headroom
    /// here is being spent on a quiet source rather than on distance. If it still is not loud
    /// enough on device, re-master the asset to a higher RMS before raising this much
    /// further — past roughly +10 dB the transient starts clipping instead of getting louder.
    private let contaminationGainDB: Double = 10

    /// Boosts the direct path relative to room reverb so the alert reads as a sharp, close
    /// signal rather than a distant one blurred into the environment.
    private let contaminationDirectLevelDB: Double = 3

    private init() {
        // Stays `.ambient`, and deliberately so.
        //
        // This was briefly changed to `.playback` to make the contamination alert louder.
        // `.playback` is a *primary audio* category: claiming it and activating the session
        // takes the audio route away from the system, including MRUIFeedback — the service
        // that plays visionOS's button press feedback. Starved of the route, that service
        // stalled, logging:
        //
        //     [MRUIFeedbackTypeButtonWithoutBackgroundTouchDown]
        //     Playback timed out before completion (after 17646 ms)
        //
        // and every button in the app stopped responding, because the press feedback never
        // completed. SoundManager is first touched when the immersive space opens, so the
        // symptom was "enter the workflow and nothing is tappable any more".
        //
        // The alert's loudness does not depend on this anyway — it comes from
        // SpatialAudioComponent.gain below, which runs through RealityKit's own spatial audio
        // path rather than the AVAudioSession category. `.ambient` + .mixWithOthers keeps this
        // app a good citizen of the shared route.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        if let player = players[name] {
            player.currentTime = 0
            player.volume = volume
            player.play()
            return
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[SoundManager] couldn't find \(name).\(ext) in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
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

            // Spatial audio attenuates with distance, and the detection panel the alert is
            // anchored to sits over a metre away. Raise the entity's gain so the alert
            // arrives loud at the user's head rather than at panel-ambient level.
            var spatial = anchor.spatialAudio ?? SpatialAudioComponent()
            spatial.gain = contaminationGainDB
            spatial.directLevel = contaminationDirectLevelDB
            anchor.spatialAudio = spatial

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
