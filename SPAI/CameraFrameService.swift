//
//  CameraFrameService.swift
//  SPAI
//
//  Wraps the visionOS Main Camera Access (enterprise) API. Streams live
//  passthrough frames from the Vision Pro's main camera so SPAI can run
//  detection on what the user is actually looking at — replacing the
//  upload-an-image flow on real hardware.
//
//  REQUIREMENTS (all set up off-device, by Friday):
//    1. Enterprise.license file added to the project
//    2. "Main Camera Access" capability enabled in Signing & Capabilities
//       (adds com.apple.developer.arkit.main-camera-access.allow)
//    3. NSEnterpriseMCAMUsageDescription key in Info.plist
//
//  IMPORTANT visionOS constraints:
//    - Camera access ONLY works inside an ImmersiveSpace (a green privacy
//      dot shows while active). It will NOT work in a plain window.
//    - This does NOT run in the simulator — hardware only.
//
//  This file is written against Apple's WWDC24 Main Camera API. Until the
//  entitlement + license are in place it will compile but the session
//  won't actually start (queryAuthorization will deny), which is expected.
//

import SwiftUI
import ARKit

@MainActor
@Observable
final class CameraFrameService {

    /// The most recent frame from the main camera (read-only buffer).
    /// nil until the first frame arrives (or if access is denied).
    private(set) var latestBuffer: CVReadOnlyPixelBuffer?

    /// Whether the camera session is currently running.
    private(set) var isRunning = false

    /// Set if the session failed to start (denied auth, not on hardware, etc.)
    /// so the UI can show why instead of silently showing nothing.
    private(set) var statusMessage: String?

    private var arkitSession = ARKitSession()
    private var cameraFrameProvider = CameraFrameProvider()

    /// How often we hand a frame off for detection. The camera streams many
    /// frames per second; running YOLO on every one would swamp the backend
    /// and the network. We throttle to one frame every `detectionInterval`
    /// seconds. 1.0s is a sane default for a compliance check (it's not a
    /// fast-motion game) — tune later.
    private let detectionInterval: TimeInterval = 1.0
    private var lastDetectionTime: Date = .distantPast

    /// Called with a throttled frame, so a caller (e.g. a detection driver)
    /// can send it to the backend. Set this before calling start().
    var onFrameForDetection: ((CVReadOnlyPixelBuffer) -> Void)?

    /// Start the camera session and begin streaming frames.
    /// Must be called from within an ImmersiveSpace, on hardware.
    func start() async {
        // Ask the user / system for camera permission. Without the enterprise
        // entitlement + license, this returns denied and we stop cleanly.
        let authResult = await arkitSession.queryAuthorization(for: [.cameraAccess])
        guard authResult[.cameraAccess] == .allowed else {
            statusMessage = "Camera access not authorized. Needs the Main Camera "
                + "enterprise entitlement + license, and must run on Vision Pro hardware."
            isRunning = false
            return
        }

        // Pick a supported video format for the main camera, left lens.
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

        // Stream frames. This loop runs until the task is cancelled (e.g. when
        // leaving the immersive space).
        for await frame in frameUpdates {
            guard let sample = frame.sample(for: .left) else { continue }
            // visionOS 26: `.buffer` is a CVReadOnlyPixelBuffer (immutable).
            latestBuffer = sample.buffer

            // Throttle: only forward a frame for detection every interval.
            let now = Date()
            if now.timeIntervalSince(lastDetectionTime) >= detectionInterval {
                lastDetectionTime = now
                onFrameForDetection?(sample.buffer)
            }
        }

        // Loop ended → session stopped.
        isRunning = false
    }

    /// Stop the camera session.
    func stop() {
        arkitSession.stop()
        isRunning = false
        latestBuffer = nil
    }
}
