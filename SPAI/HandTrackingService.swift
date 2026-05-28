//
//  HandTrackingService.swift
//  SPAI
//
//  SCRUM-50 spike: confirm we can read hand joint positions from ARKit
//  on visionOS and print them. Proves the data is available for future
//  contamination / hand-pose logic.
//

import ARKit
import SwiftUI

@MainActor
@Observable
final class HandTrackingService {
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()

    // Latest readings, exposed so a view could display them later.
    var leftWristPosition: SIMD3<Float>?
    var rightWristPosition: SIMD3<Float>?
    var isTracking = false

    /// Request authorization and start the ARKit session.
    func start() async {
        // Hand tracking needs explicit authorization on visionOS.
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

    /// Listen for hand anchor updates and print joint positions.
    private func processUpdates() async {
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor

            // Only use tracked hands (skip when hand leaves view).
            guard anchor.isTracked else { continue }

            // The wrist joint is a good single reference point for the spike.
            if let wrist = anchor.handSkeleton?.joint(.wrist) {
                // Joint transform is relative to the anchor; combine with
                // the anchor's world transform for a world-space position.
                let worldTransform = anchor.originFromAnchorTransform
                let wristTransform = wrist.anchorFromJointTransform
                let combined = worldTransform * wristTransform
                let position = SIMD3<Float>(
                    combined.columns.3.x,
                    combined.columns.3.y,
                    combined.columns.3.z
                )

                switch anchor.chirality {
                case .left:
                    leftWristPosition = position
                    print("[hand-tracking] LEFT wrist: \(position)")
                case .right:
                    rightWristPosition = position
                    print("[hand-tracking] RIGHT wrist: \(position)")
                }
            }
        }
    }
}
