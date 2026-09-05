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

    /// Eye height to lay the panel arc out against.
    var eyeHeight: Float { calibratedEyeHeight ?? Self.defaultEyeHeight }

    #if !targetEnvironment(simulator)
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var isRunning = false
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

        if !isRunning {
            do {
                try await session.run([worldTracking])
                isRunning = true
            } catch {
                print("[head-anchor] world tracking failed to start: \(error)")
                return
            }
        }

        // The provider needs a moment after `run` before it reports a device anchor.
        for _ in 0..<30 {
            if let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                let m = anchor.originFromAnchorTransform
                calibratedEyeHeight = m.columns.3.y
                // -Z is forward for the device transform.
                calibratedYaw = atan2(-m.columns.2.x, -m.columns.2.z)
                print("[head-anchor] calibrated eye height \(m.columns.3.y) m")
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        print("[head-anchor] no device anchor after 1.5s; using default eye height")
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        guard isRunning else { return }
        session.stop()
        isRunning = false
        #endif
    }
}
