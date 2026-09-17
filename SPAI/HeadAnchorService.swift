//
//  HeadAnchorService.swift
//  SPAI
//

import ARKit
import QuartzCore
import SwiftUI

/// Samples where the user's head actually is, so panel placement can be anchored to their
/// eye line instead of to an assumed world origin.
///
/// The panel arc used to hard-code absolute heights (status bar at y = 1.9, workflow at 0.85)
/// on the assumption that y = 0 is the floor and the wearer's eyes are at roughly 1.5 m. When
/// that assumption is off — a shorter or seated user, or a recentre that moves the origin —
/// the whole arc slides relative to the user, which is the most likely reason the status bar
/// was reported at the bottom of the field of view rather than at top centre.
///
/// Calibrating once when the immersive space opens keeps panels in fixed world positions
/// (they still must not follow the user around) while making "above eye line" mean the same
/// thing for everyone.
///
/// Two things make that calibration easy to get wrong on device, and both are invisible in the
/// simulator — where there is no sample at all and the arc quietly uses `defaultEyeHeight`:
///
/// 1. `session.run` returns when the *request* is accepted, not when the provider is running.
///    Anything that queries a device anchor in between logs "the device_anchor can only be
///    queried when the world tracking provider is running" and gets nothing back.
/// 2. The first anchor that does come back can still be mid-convergence. Its height is junk,
///    and the arc is laid out against whatever number we accept — a sample 0.7 m low puts the
///    bottom of the arc on the floor.
@MainActor
@Observable
final class HeadAnchorService {
    /// Height in metres of the user's eyes above the scene origin, measured at calibration.
    /// `nil` until a sample succeeds; callers fall back to `defaultEyeHeight`.
    private(set) var calibratedEyeHeight: Float?

    /// Forward direction the user was facing at calibration, flattened to horizontal.
    private(set) var calibratedYaw: Float?

    /// Used when calibration has not produced a sample — an average standing adult eye height.
    static let defaultEyeHeight: Float = 1.5

    /// Heights a device anchor can plausibly report for a wearer — standing or seated — above
    /// a floor-level world origin. A sample below this is not a very short user: it means
    /// tracking had not converged, or the origin is not on the floor. Trusting it sinks the
    /// arc, so we would rather be a little off for a seated user than put the workflow panel
    /// at ankle height.
    static let plausibleEyeHeights: ClosedRange<Float> = 1.0...2.2

    /// Eye height to lay the panel arc out against.
    var eyeHeight: Float { calibratedEyeHeight ?? Self.defaultEyeHeight }

    /// Live head position, queried on demand. Wrist gestures need it every frame — "am I
    /// holding my wrist up to look at it" is a question about the wrist *relative to the
    /// face*, not about the wrist alone.
    ///
    /// Returns `nil` in the simulator and before world tracking has a fix.
    func currentHeadPosition() -> SIMD3<Float>? {
        #if targetEnvironment(simulator)
        return nil
        #else
        // Ask the provider for its state rather than trusting a flag we set ourselves. Hand
        // tracking calls this every frame, so a flag that says "running" a few frames early
        // is worth one console error per frame.
        guard worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        else { return nil }
        let m = anchor.originFromAnchorTransform
        return SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        #endif
    }

    #if !targetEnvironment(simulator)
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var hasStartedSession = false
    #endif

    /// Starts world tracking and takes an eye-height sample. Safe to call more than once —
    /// later calls re-sample without restarting the provider.
    func calibrate() async {
        #if targetEnvironment(simulator)
        // WorldTrackingProvider gives no meaningful device pose in the simulator, so the
        // arc uses the default eye height there. This is why panel heights must stay
        // sensible with `defaultEyeHeight` and not depend on a real sample existing.
        calibratedEyeHeight = nil
        #else
        guard WorldTrackingProvider.isSupported else { return }

        if !hasStartedSession {
            do {
                try await session.run([worldTracking])
                hasStartedSession = true
            } catch {
                SPAILog.error(.headAnchor, "world tracking failed to start: \(error)")
                return
            }
        }

        guard await waitUntilRunning() else {
            SPAILog.error(.headAnchor, "world tracking never reached .running; using default eye height")
            return
        }

        guard let sample = await settledSample() else {
            SPAILog.error(.headAnchor, "no settled device anchor; using default eye height")
            return
        }

        // Yaw survives a rejected height — the two failures are unrelated.
        calibratedYaw = sample.yaw

        guard Self.plausibleEyeHeights.contains(sample.height) else {
            SPAILog.error(.headAnchor, """
            rejecting eye height \(sample.height) m — outside \
            \(Self.plausibleEyeHeights.lowerBound)...\(Self.plausibleEyeHeights.upperBound) m. \
            The world origin is probably not at floor level. Using default \
            \(Self.defaultEyeHeight) m.
            """)
            calibratedEyeHeight = nil
            return
        }

        calibratedEyeHeight = sample.height
        SPAILog.info(.headAnchor, "calibrated eye height \(sample.height) m")
        #endif
    }

    #if !targetEnvironment(simulator)
    /// Waits for the provider to actually reach `.running`, up to ~2 s.
    private func waitUntilRunning() async -> Bool {
        for _ in 0..<40 {
            switch worldTracking.state {
            case .running: return true
            case .stopped: return false
            default: break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return worldTracking.state == .running
    }

    /// Samples the device anchor until three consecutive readings agree to within 2 cm, so the
    /// arc is laid out against a converged pose rather than the first number ARKit offers.
    /// Falls back to the last reading seen if nothing settles inside the budget.
    private func settledSample() async -> (height: Float, yaw: Float)? {
        var previousHeight: Float?
        var agreements = 0
        var latest: (height: Float, yaw: Float)?

        for _ in 0..<30 {
            if let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                let m = anchor.originFromAnchorTransform
                let height = m.columns.3.y
                // -Z is forward for the device transform.
                let yaw = atan2(-m.columns.2.x, -m.columns.2.z)
                latest = (height, yaw)

                if let previousHeight, abs(height - previousHeight) < 0.02 {
                    agreements += 1
                    if agreements >= 2 { return (height, yaw) }
                } else {
                    agreements = 0
                }
                previousHeight = height
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        if let latest {
            SPAILog.error(.headAnchor, "eye height never settled; last reading \(latest.height) m")
        }
        return latest
    }
    #endif

    func stop() {
        #if !targetEnvironment(simulator)
        guard hasStartedSession else { return }
        session.stop()
        hasStartedSession = false
        #endif
    }
}
