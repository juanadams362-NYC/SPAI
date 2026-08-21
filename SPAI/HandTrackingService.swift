//
//  HandTrackingService.swift
//  SPAI
//

import ARKit
import SwiftUI

@MainActor
@Observable
final class HandTrackingService {
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()

    var leftWristPosition: SIMD3<Float>?
    var rightWristPosition: SIMD3<Float>?
    var leftWristPose: (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)?
    var rightWristPose: (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)?
    var isTracking = false

    private let smoothingAlpha: Float = 0.25

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private func smooth(_ new: SIMD3<Float>, with current: SIMD3<Float>?) -> SIMD3<Float> {
        guard let current else { return new }
        return mix(current, new, t: smoothingAlpha)
    }

    func start() async {
        guard HandTrackingProvider.isSupported else {
            print("[hand-tracking] not supported on this device")
            return
        }

        do {
            try await session.run([handTracking])
            isTracking = true
            print("[hand-tracking] session started")
            await processUpdates()
        } catch {
            print("[hand-tracking] failed to start: \(error)")
        }
    }

    private func processUpdates() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor

            guard anchor.isTracked else { continue }

            if let wrist = anchor.handSkeleton?.joint(.wrist) {
                let worldTransform = anchor.originFromAnchorTransform
                let wristTransform = wrist.anchorFromJointTransform
                let combined = worldTransform * wristTransform

                let rawPosition = SIMD3<Float>(
                    combined.columns.3.x,
                    combined.columns.3.y,
                    combined.columns.3.z
                )
                let rawUp = normalize(SIMD3<Float>(
                    combined.columns.1.x,
                    combined.columns.1.y,
                    combined.columns.1.z
                ))
                let rawForward = normalize(SIMD3<Float>(
                    combined.columns.2.x,
                    combined.columns.2.y,
                    combined.columns.2.z
                ))

                switch anchor.chirality {
                case .left:
                    let pos = smooth(rawPosition, with: leftWristPose?.position)
                    let up = normalize(smooth(rawUp, with: leftWristPose?.up))
                    let fwd = normalize(smooth(rawForward, with: leftWristPose?.forward))
                    leftWristPose = (pos, fwd, up)
                    leftWristPosition = pos
                    print("[hand-tracking] LEFT wrist: \(pos)")
                case .right:
                    let pos = smooth(rawPosition, with: rightWristPose?.position)
                    let up = normalize(smooth(rawUp, with: rightWristPose?.up))
                    let fwd = normalize(smooth(rawForward, with: rightWristPose?.forward))
                    rightWristPose = (pos, fwd, up)
                    rightWristPosition = pos
                    print("[hand-tracking] RIGHT wrist: \(pos)")
                }
            }
        }
    }
}
