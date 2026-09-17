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
        // `queryAuthorization` only reads the current status — it never prompts. Main Camera
        // Access is an Enterprise entitlement, and until the first prompt has been answered
        // the status is `.notDetermined` forever, which reads identically to "not
        // authorized" and would look broken even once the entitlement is fully provisioned.
        // `requestAuthorization` is the one that actually surfaces the system prompt when
        // needed, and still just returns the existing status if the user already answered.
        let authResult = await arkitSession.requestAuthorization(for: [.cameraAccess])
        let status = authResult[.cameraAccess]
        guard status == .allowed else {
            statusMessage = "Camera access not authorized. Needs the Main Camera "
                + "enterprise entitlement + license, and must run on Vision Pro hardware."
            isRunning = false
            SPAILog.error(.camera, "not authorized (\(status?.description ?? "unknown")) — needs the Main Camera entitlement + license, and Vision Pro hardware")
            return
        }

        let formats = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left])
        guard let format = formats.first else {
            statusMessage = "No supported camera format found."
            SPAILog.error(.camera, "no supported video format for .main / .left")
            return
        }

        do {
            try await arkitSession.run([cameraFrameProvider])
        } catch {
            statusMessage = "Failed to start camera session: \(error.localizedDescription)"
            isRunning = false
            SPAILog.error(.camera, "session failed to start: \(error.localizedDescription)")
            return
        }

        guard let frameUpdates = cameraFrameProvider.cameraFrameUpdates(for: format) else {
            statusMessage = "Couldn't get camera frame updates."
            isRunning = false
            SPAILog.error(.camera, "cameraFrameUpdates(for:) returned nil after a successful session run")
            return
        }

        isRunning = true
        statusMessage = nil
        SPAILog.info(.camera, "session started")

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
