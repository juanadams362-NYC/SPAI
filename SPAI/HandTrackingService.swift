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

    /// Whether each wrist is currently held in its summoning posture — see `WristGesture`.
    /// The panels key off these rather than off raw tracking, so they appear when asked for
    /// instead of whenever a hand happens to be in frame.
    private(set) var leftWristPresented = false
    private(set) var rightWristPresented = false

    /// Supplies the head position the gesture test needs. Set by ImmersiveView.
    var headPositionProvider: (() -> SIMD3<Float>?)?

    // Lower alpha = more smoothing (less jitter). 0.15 gives ~7-frame lag at 90fps.
    private let smoothingAlpha: Float = 0.15

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

            // Losing tracking used to `continue`, which left the last known pose in place —
            // so a wrist panel froze mid-air when the arm left the camera's view instead of
            // fading out. Clear the pose for that hand so the panel knows it's gone.
            guard anchor.isTracked else {
                switch anchor.chirality {
                case .left:
                    leftWristPose = nil
                    leftWristPosition = nil
                    leftWristPresented = false
                case .right:
                    rightWristPose = nil
                    rightWristPosition = nil
                    rightWristPresented = false
                }
                continue
            }

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

                let head = headPositionProvider?()

                switch anchor.chirality {
                case .left:
                    let pos = smooth(rawPosition, with: leftWristPose?.position)
                    let up = normalize(smooth(rawUp, with: leftWristPose?.up))
                    let fwd = normalize(smooth(rawForward, with: leftWristPose?.forward))
                    let pose = (position: pos, forward: fwd, up: up)
                    leftWristPose = pose
                    leftWristPosition = pos
                    // "Book resting along the inner forearm": held level and turned to face you.
                    leftWristPresented = WristGesture.isPresented(
                        pose: pose,
                        headPosition: head,
                        wasPresented: leftWristPresented,
                        requireLevelForearm: true
                    )
                case .right:
                    let pos = smooth(rawPosition, with: rightWristPose?.position)
                    let up = normalize(smooth(rawUp, with: rightWristPose?.up))
                    let fwd = normalize(smooth(rawForward, with: rightWristPose?.forward))
                    let pose = (position: pos, forward: fwd, up: up)
                    rightWristPose = pose
                    rightWristPosition = pos
                    // "Checking the time": turned to face you, at any comfortable arm angle.
                    rightWristPresented = WristGesture.isPresented(
                        pose: pose,
                        headPosition: head,
                        wasPresented: rightWristPresented,
                        requireLevelForearm: false
                    )
                }
            }
        }
    }
}
