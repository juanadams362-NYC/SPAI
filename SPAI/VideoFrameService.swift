//
//  VideoFrameService.swift
//  SPAI
//
//  Created by Juan Adams on 7/28/26.
//

import AVFoundation
import UIKit
import SwiftUI

@MainActor
@Observable
final class VideoFrameService {
    private var player: AVPlayer?
    private var generator: AVAssetImageGenerator?
    private var timer: Timer?
    private var isDetecting = false
    private var duration: Double = 0

    var isRunning = false
    var framesProcessed = 0
    var currentTime: Double = 0

    var onFrame: ((UIImage) async -> Void)?

    func start(url: URL, player: AVPlayer, interval: Double = 1.0) async {
        stop()
        self.player = player

        let asset = AVURLAsset(url: url)
        duration = (try? await asset.load(.duration).seconds) ?? 0
        if !duration.isFinite { duration = 0 }
        print("[VideoFrameService] duration from asset: \(duration)s")

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator = gen

        framesProcessed = 0
        currentTime = 0
        isRunning = true
        await player.seek(to: .zero)
        player.play()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.pause()
        isRunning = false
    }

    private var effectiveDuration: Double {
        if duration > 0 { return duration }
        let itemSeconds = player?.currentItem?.duration.seconds ?? 0
        return itemSeconds.isFinite ? itemSeconds : 0
    }

    private func sample() async {
        guard let player, let generator else { return }
        guard !isDetecting else { return }

        let time = player.currentTime()
        currentTime = time.seconds.isFinite ? time.seconds : 0

        let total = effectiveDuration
        if total > 0 && currentTime >= total - 0.1 {
            print("[VideoFrameService] reached end at \(currentTime)s, \(framesProcessed) frames")
            stop()
            return
        }

        if framesProcessed >= 200 {
            print("[VideoFrameService] frame backstop hit, stopping")
            stop()
            return
        }

        isDetecting = true
        defer { isDetecting = false }

        do {
            let cgImage = try await generator.image(at: time).image
            let frame = UIImage(cgImage: cgImage)
            framesProcessed += 1
            await onFrame?(frame)
        } catch {
            print("[VideoFrameService] frame grab failed at \(currentTime)s: \(error)")
        }
    }
}
