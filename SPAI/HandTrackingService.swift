//
//  HandTrackingService.swift
//  SPAI
//

import ARKit
import QuartzCore
import SwiftUI

@MainActor
@Observable
final class HandTrackingService {
    typealias WristPose = (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)

    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()

    var leftWristPosition: SIMD3<Float>?
    var rightWristPosition: SIMD3<Float>?
    var leftWristPose: WristPose?
    var rightWristPose: WristPose?
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

    // MARK: - Publication rate
    //
    // Publishing every anchor update is what made the app untappable on device.
    //
    // ARKit delivers hand anchors per hand at display rate — up to ~180 updates a second
    // across both — and each one wrote straight to the `@Observable` properties above. Every
    // write invalidates the views observing them, which re-runs ImmersiveView's RealityView
    // update closure in full: a billboard component write per panel, both wrist re-anchors,
    // the tour card, the eye-height check. At 180 Hz that saturates the main actor, and a
    // starved main actor cannot finish a button press — MRUIFeedback's press feedback times
    // out ("Playback timed out before completion") and the tap is dropped. Every control in
    // the immersive space reads as dead while the hands are visible.
    //
    // This never showed up in the simulator because hand tracking never runs there:
    // ImmersiveView starts it inside `#if !targetEnvironment(simulator)`.
    //
    // 30 Hz is far more than the wrist panels need, and leaves the main actor free.
    private let publishInterval: TimeInterval = 1.0 / 30.0
    private var lastPublished: TimeInterval = 0

    /// The head is re-sampled far less often than hands arrive. Asking for the device anchor
    /// once per hand update put ~180 ARKit queries a second on the main actor, to answer "is
    /// the wrist raised toward the face" — a question the head barely moves on.
    private let headSampleInterval: TimeInterval = 1.0 / 15.0
    private var lastHeadSample: TimeInterval = 0
    private var cachedHead: SIMD3<Float>?

    /// Smoothed poses held outside the `@Observable` properties so the filter keeps running at
    /// the full anchor rate while only its throttled result is published. Running the filter
    /// itself at 30 Hz would have changed its dynamics — the panels would lag differently —
    /// and this keeps them identical to before.
    private var leftSmoothed: WristPose?
    private var rightSmoothed: WristPose?
    private var leftPresentedPending = false
    private var rightPresentedPending = false

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private func smooth(_ new: SIMD3<Float>, with current: SIMD3<Float>?) -> SIMD3<Float> {
        guard let current else { return new }
        return mix(current, new, t: smoothingAlpha)
    }

    func start() async {
        guard HandTrackingProvider.isSupported else {
            SPAILog.error(.handTracking, "not supported on this device")
            return
        }

        do {
            try await session.run([handTracking])
            isTracking = true
            SPAILog.info(.handTracking, "session started")
            await processUpdates()
        } catch {
            SPAILog.error(.handTracking, "failed to start: \(error)")
        }
    }

    private func processUpdates() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            let now = CACurrentMediaTime()

            // Losing tracking used to `continue`, which left the last known pose in place —
            // so a wrist panel froze mid-air when the arm left the camera's view instead of
            // fading out. Clear the pose for that hand so the panel knows it's gone.
            guard anchor.isTracked else {
                switch anchor.chirality {
                case .left:
                    leftSmoothed = nil
                    leftPresentedPending = false
                case .right:
                    rightSmoothed = nil
                    rightPresentedPending = false
                }
                // A hand disappearing has a fade to start, so it is published immediately
                // rather than waiting out the interval.
                publish(force: true, at: now)
                continue
            }

            guard let wrist = anchor.handSkeleton?.joint(.wrist) else { continue }

            let combined = anchor.originFromAnchorTransform * wrist.anchorFromJointTransform

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

            let head = headPosition(at: now)

            switch anchor.chirality {
            case .left:
                let pose = smoothed(rawPosition, up: rawUp, forward: rawForward, from: leftSmoothed)
                leftSmoothed = pose
                // "Book resting along the inner forearm": held level and turned to face you.
                let presented = WristGesture.isPresented(
                    pose: pose,
                    headPosition: head,
                    wasPresented: leftPresentedPending,
                    requireLevelForearm: true
                )
                let changed = presented != leftPresentedPending
                leftPresentedPending = presented
                // A menu appearing or dismissing should feel immediate; a wrist drifting a
                // few millimetres can wait for the next interval.
                publish(force: changed, at: now)
            case .right:
                let pose = smoothed(rawPosition, up: rawUp, forward: rawForward, from: rightSmoothed)
                rightSmoothed = pose
                // "Checking the time": turned to face you, at any comfortable arm angle.
                let presented = WristGesture.isPresented(
                    pose: pose,
                    headPosition: head,
                    wasPresented: rightPresentedPending,
                    requireLevelForearm: false
                )
                let changed = presented != rightPresentedPending
                rightPresentedPending = presented
                publish(force: changed, at: now)
            }
        }
    }

    private func smoothed(
        _ position: SIMD3<Float>,
        up: SIMD3<Float>,
        forward: SIMD3<Float>,
        from current: WristPose?
    ) -> WristPose {
        (
            position: smooth(position, with: current?.position),
            forward: normalize(smooth(forward, with: current?.forward)),
            up: normalize(smooth(up, with: current?.up))
        )
    }

    private func headPosition(at now: TimeInterval) -> SIMD3<Float>? {
        guard now - lastHeadSample >= headSampleInterval else { return cachedHead }
        lastHeadSample = now
        cachedHead = headPositionProvider?()
        return cachedHead
    }

    /// Copies the smoothed state into the observed properties — the only place in this type
    /// that touches them, and the only place that costs a SwiftUI invalidation.
    private func publish(force: Bool, at now: TimeInterval) {
        guard force || now - lastPublished >= publishInterval else { return }
        lastPublished = now

        leftWristPose = leftSmoothed
        leftWristPosition = leftSmoothed?.position
        leftWristPresented = leftPresentedPending

        rightWristPose = rightSmoothed
        rightWristPosition = rightSmoothed?.position
        rightWristPresented = rightPresentedPending
    }
}
