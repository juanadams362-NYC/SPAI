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
        // Do NOT configure the shared AVAudioSession here.
        //
        // History of every attempt and why it broke buttons:
        //
        //   1. `.playback` + `setActive(true)` — primary-audio category claims the hardware
        //      route exclusively. MRUIFeedback (visionOS button-press haptics) can't get the
        //      route and stalls:
        //          [MRUIFeedbackTypeButtonWithoutBackgroundTouchDown]
        //          Playback timed out before completion (after 17 646 ms)
        //      Every button in the app stopped responding.
        //
        //   2. `.ambient` + `setActive(true)` — shorter timeout, same symptom:
        //          Playback timed out before completion (after 2 074 ms)
        //
        //   3. `.ambient` + no `setActive` — calling `setCategory` alone (without activation)
        //      is still enough to alter the session state that visionOS exposes to MRUIFeedback.
        //      The timeout dropped to ~2 034 ms but remained:
        //          Playback timed out before completion (after 2 034 ms)
        //
        // Root cause: any `setCategory` call — even without `setActive` — notifies the system
        // audio daemon that this app is configuring audio. In visionOS the daemon tracks
        // per-app session config to arbitrate the shared route for system-feedback services.
        // Touching the config is enough to create contention.
        //
        // Fix: leave the session entirely alone. The system default (.soloAmbient, inactive)
        // lets MRUIFeedback use the route freely. AVAudioPlayer and RealityKit's spatial audio
        // both configure and activate the session themselves when they actually play, and the
        // daemon restores the route to system services when those apps go silent again.
        let session = AVAudioSession.sharedInstance()
        SPAILog.debug(.sound, "SoundManager init — session untouched (cat=\(session.category.rawValue) opts=\(session.categoryOptions.rawValue))")
    }

    func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        if let player = players[name] {
            player.currentTime = 0
            player.volume = volume
            player.play()
            return
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            SPAILog.error(.sound, "couldn't find \(name).\(ext) in bundle")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            players[name] = player
            player.play()
        } catch {
            SPAILog.error(.sound, "failed to load \(name).\(ext): \(error)")
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
            SPAILog.error(.sound, "spatial playback failed, falling back to flat audio: \(error)")
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
