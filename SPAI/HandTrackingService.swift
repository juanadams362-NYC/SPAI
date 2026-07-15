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
    var isTracking = false

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
