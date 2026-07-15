//
//  CameraFrameService.swift
//  SPAI
//

import SwiftUI
import ARKit

@MainActor
@Observable
final class CameraFrameService {

    private(set) var latestBuffer: CVReadOnlyPixelBuffer?

    private(set) var isRunning = false

    private(set) var statusMessage: String?

    private var arkitSession = ARKitSession()
    private var cameraFrameProvider = CameraFrameProvider()

    private let detectionInterval: TimeInterval = 1.0
    private var lastDetectionTime: Date = .distantPast

    var onFrameForDetection: ((CVReadOnlyPixelBuffer) -> Void)?

    func start() async {
        let authResult = await arkitSession.queryAuthorization(for: [.cameraAccess])
        guard authResult[.cameraAccess] == .allowed else {
            statusMessage = "Camera access not authorized. Needs the Main Camera "
                + "enterprise entitlement + license, and must run on Vision Pro hardware."
            isRunning = false
            return
        }

        let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
        guard let format = formats.first else {
            statusMessage = "No supported camera format found."
            return
        }

        do {
            try await arkitSession.run([cameraFrameProvider])
        } catch {
            statusMessage = "Failed to start camera session: \(error.localizedDescription)"
            isRunning = false
            return
        }

        guard let frameUpdates = cameraFrameProvider.cameraFrameUpdates(for: format) else {
            statusMessage = "Couldn't get camera frame updates."
            isRunning = false
            return
        }

        isRunning = true
        statusMessage = nil

        for await frame in frameUpdates {
            guard let sample = frame.sample(for: .left) else { continue }
            latestBuffer = sample.buffer

            let now = Date()
            if now.timeIntervalSince(lastDetectionTime) >= detectionInterval {
                lastDetectionTime = now
                onFrameForDetection?(sample.buffer)
            }
        }

        isRunning = false
    }

    func stop() {
        arkitSession.stop()
        isRunning = false
        latestBuffer = nil
    }
}
