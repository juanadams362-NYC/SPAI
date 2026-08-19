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
    private var sampleInterval: Double = 1.0
    private var lastFingerprint: [UInt8]?
    private var isPausedForContamination = false

    private let maxProcessedFrames = 100
    private let longVideoThreshold: Double = 120.0 // 2 minutes

    var isRunning = false
    var framesProcessed = 0
    var framesSkipped = 0
    var currentTime: Double = 0
    
    // State tracking for logging
    private var lastGloveState: String?
    var stateTransitions: [(timestamp: Double, state: String)] = []

    var onFrame: ((UIImage) async -> Void)?
    var preferOnDeviceForLongVideos: Bool = true

    func start(url: URL, player: AVPlayer, interval: Double = 1.0) async {
        stop()
        self.player = player

        let asset = AVURLAsset(url: url)
        duration = (try? await asset.load(.duration).seconds) ?? 0
        if !duration.isFinite { duration = 0 }
        sampleInterval = duration > 0
            ? max(duration / Double(maxProcessedFrames), 0.1)
            : interval
        
        // Reset state tracking
        lastGloveState = nil
        stateTransitions = []
        
        let isLong = isLongVideo()
        print("[VideoFrameService] duration from asset: \(duration)s")
        if isLong {
            print("⚠️ [VideoFrameService] Long video detected (\(Int(duration))s > \(Int(longVideoThreshold))s)")
            if preferOnDeviceForLongVideos {
                print("💡 [VideoFrameService] Routing to on-device model to avoid excessive cloud calls")
            }
        }
        print("[VideoFrameService] Sample interval: \(String(format: "%.2f", sampleInterval))s (max \(maxProcessedFrames) frames)")

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator = gen

        framesProcessed = 0
        framesSkipped = 0
        currentTime = 0
        lastFingerprint = nil
        isPausedForContamination = false
        isRunning = true
        await player.seek(to: .zero)
        player.play()

        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.pause()
        isRunning = false
        isPausedForContamination = false
        lastFingerprint = nil
        
        // Print summary of state transitions
        if !stateTransitions.isEmpty {
            print("📊 [VideoFrameService] State transitions summary:")
            for (timestamp, state) in stateTransitions {
                let minutes = Int(timestamp / 60)
                let seconds = Int(timestamp.truncatingRemainder(dividingBy: 60))
                print("   \(String(format: "%02d:%02d", minutes, seconds)) - \(state)")
            }
        }
    }
    
    func logStateTransition(state: String, at time: Double) {
        guard state != lastGloveState else { return }
        lastGloveState = state
        stateTransitions.append((timestamp: time, state: state))
        
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        print("🔄 [VideoFrameService] State change at \(String(format: "%02d:%02d", minutes, seconds)): \(state)")
    }
    
    func isLongVideo() -> Bool {
        return duration > longVideoThreshold
    }

    func pauseForContamination() {
        guard isRunning, !isPausedForContamination else { return }
        timer?.invalidate()
        timer = nil
        player?.pause()
        isPausedForContamination = true
    }

    func resumeAfterContamination() {
        guard isRunning, isPausedForContamination else { return }
        isPausedForContamination = false
        player?.play()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sample() }
        }
    }

    private var effectiveDuration: Double {
        if duration > 0 { return duration }
        let itemSeconds = player?.currentItem?.duration.seconds ?? 0
        return itemSeconds.isFinite ? itemSeconds : 0
    }

    private func sample() async {
        guard let player, let generator else { return }
        guard !isDetecting else { return }
        guard !isPausedForContamination else { return }

        let time = player.currentTime()
        currentTime = time.seconds.isFinite ? time.seconds : 0

        let total = effectiveDuration
        if total > 0 && currentTime >= total - 0.1 {
            print("[VideoFrameService] reached end at \(currentTime)s, \(framesProcessed) frames")
            stop()
            return
        }

        if framesProcessed >= maxProcessedFrames {
            print("[VideoFrameService] frame backstop hit, stopping")
            stop()
            return
        }

        isDetecting = true
        defer { isDetecting = false }

        do {
            let cgImage = try await generator.image(at: time).image
            let frame = UIImage(cgImage: cgImage)
            guard shouldProcess(frame) else {
                framesSkipped += 1
                return
            }
            framesProcessed += 1
            await onFrame?(frame)
        } catch {
            print("[VideoFrameService] frame grab failed at \(currentTime)s: \(error)")
        }
    }

    private func shouldProcess(_ image: UIImage) -> Bool {
        guard let fingerprint = fingerprint(for: image) else { return true }
        defer { lastFingerprint = fingerprint }

        guard let lastFingerprint, lastFingerprint.count == fingerprint.count else {
            return true
        }

        let totalDelta = zip(lastFingerprint, fingerprint).reduce(0) { sum, pair in
            sum + abs(Int(pair.0) - Int(pair.1))
        }
        let averageDelta = Double(totalDelta) / Double(fingerprint.count)
        return averageDelta >= 4
    }

    private func fingerprint(for image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }

        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
