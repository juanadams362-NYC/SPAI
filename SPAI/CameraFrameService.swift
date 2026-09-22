//
//  CameraFrameService.swift
//  SPAI
//

import SwiftUI
import ARKit
import VisionEntitlementServices

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

    /// Called with a zone-cropped, ready-to-use UIImage at most once per `detectionInterval`,
    /// and only while the head-stability gate is open. Callers no longer need to do the
    /// pixel-buffer conversion — that happens here alongside the crop.
    var onFrameForDetection: ((UIImage) -> Void)?

    /// Returns the current head yaw in radians, or nil if tracking is unavailable.
    /// Supplied by ImmersiveView, which owns HeadAnchorService.
    /// When nil the gate is bypassed — tracking loss must not suppress safety alerts.
    var headYawProvider: (() -> Float?)?

    // MARK: - Head stability state

    /// The yaw value when the head most recently entered the stable region.
    private var stableReferenceYaw: Float?

    /// When the head most recently entered (or re-entered) the stable region.
    private var stableFrom: Date?

    // MARK: - Lifecycle

    func start() async {
        // `queryAuthorization` only reads the current status — it never prompts. Main Camera
        // Access is an Enterprise entitlement, and until the first prompt has been answered
        // the status is `.notDetermined` forever, which reads identically to "not
        // authorized" and would look broken even once the entitlement is fully provisioned.
        // `requestAuthorization` is the one that actually surfaces the system prompt when
        // needed, and still just returns the existing status if the user already answered.
        let authResult = await arkitSession.requestAuthorization(for: [.cameraAccess])
        let status = authResult[.cameraAccess]
        // Log success too — "not authorized" and "authorized but no formats" both produce
        // no camera output, and the only way to distinguish them in the log is this line.
        SPAILog.info(.camera, "authorization: \(status?.description ?? "unknown")")
        guard status == .allowed else {
            statusMessage = "Camera access not authorized. Needs the Main Camera "
                + "enterprise entitlement + license, and must run on Vision Pro hardware."
            isRunning = false
            SPAILog.error(.camera, "not authorized (\(status?.description ?? "unknown")) — needs the Main Camera entitlement + license, and Vision Pro hardware")
            return
        }

        // Check the enterprise license state before attempting the format query.
        // This gives us a direct, unambiguous answer about what the XPC sandbox
        // restriction actually means, rather than inferring it from an empty format list.
        let licenseStatus = EnterpriseLicenseDetails.shared.licenseStatus
        let cameraApproved = EnterpriseLicenseDetails.shared.isApproved(for: .mainCameraAccess)
        SPAILog.info(.camera, "enterprise license: \(licenseStatus), mainCameraAccess approved: \(cameraApproved)")
        if licenseStatus != .valid {
            SPAILog.error(.camera, "enterprise license not valid (status: \(licenseStatus)) — camera will not produce formats")
        } else if !cameraApproved {
            SPAILog.error(.camera, "enterprise license valid but mainCameraAccess not approved — check the entitlement request with Apple")
        }

        // Try camera position combinations in priority order.
        //
        // On some hardware or OS versions, only specific position sets expose formats —
        // querying only [.left] returns empty even when the entitlement is valid. The most
        // common cause of "no supported video format" is the enterprise license runtime
        // check failing (com.apple.enterprise.licensing XPC sandbox restriction), but a
        // wrong position query is the one thing we can fix in code without reprovisioning.
        let candidates: [(positions: [CameraFrameProvider.CameraPosition],
                          primary: CameraFrameProvider.CameraPosition,
                          label: String)] = [
            ([.left],         .left,  ".left"),
            ([.right],        .right, ".right"),
            ([.left, .right], .left,  ".left+.right"),
        ]

        var chosenFormat: CameraVideoFormat? = nil
        var samplePosition: CameraFrameProvider.CameraPosition = .left

        for candidate in candidates {
            let fmts = CameraVideoFormat.supportedVideoFormats(
                for: .main, cameraPositions: candidate.positions)
            SPAILog.info(.camera, "formats for \(candidate.label): \(fmts.count)")
            if let first = fmts.first {
                chosenFormat = first
                samplePosition = candidate.primary
                SPAILog.info(.camera, "selected format for \(candidate.label)")
                break
            }
        }

        guard let format = chosenFormat else {
            statusMessage = "No supported camera format found. "
                + "Verify the Enterprise license profile is installed on this device "
                + "and the Main Camera Access entitlement is in the provisioning profile."
            isRunning = false
            SPAILog.error(.camera, "no supported video format for any position — enterprise license may not be installed on device")
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
        SPAILog.info(.camera, "session started — position \(samplePosition), zone \(Int(DetectionTuning.detectionZoneWidthFraction * 100))%×\(Int(DetectionTuning.detectionZoneHeightFraction * 100))%, stability gate \(DetectionTuning.headYawStableSeconds)s / \(DetectionTuning.headYawThresholdDegrees)°")

        for await frame in frameUpdates {
            guard let sample = frame.sample(for: samplePosition) else { continue }
            latestBuffer = sample.buffer

            let now = Date()
            guard now.timeIntervalSince(lastDetectionTime) >= detectionInterval else { continue }

            // ── Head stability gate ────────────────────────────────────────────────────
            //
            // Only send a frame to detection when the wearer's head has been pointing in
            // roughly the same direction for at least `headYawStableSeconds`. A brief
            // glance to the side resets the clock; sustained gaze on the bench opens it.
            //
            // The gate is bypassed completely when `headYawProvider` is nil (simulator)
            // or returns nil (tracking momentarily unavailable) — tracking loss must never
            // prevent a safety alert from the frame that's actually in front of the user.
            if let provider = headYawProvider, let currentYaw = provider() {
                if let reference = stableReferenceYaw {
                    let deltaDeg = abs(wrappedAngleDelta(currentYaw, reference)) * (180 / Float.pi)
                    if deltaDeg > DetectionTuning.headYawThresholdDegrees {
                        // Head moved outside the stable window — reset the clock.
                        stableReferenceYaw = currentYaw
                        stableFrom = now
                        SPAILog.debug(.camera, "head moved \(String(format: "%.1f", deltaDeg))° — stability gate reset")
                        continue
                    }
                    // Head is within threshold; check if it has been stable long enough.
                    let stableDuration = now.timeIntervalSince(stableFrom ?? now)
                    guard stableDuration >= DetectionTuning.headYawStableSeconds else {
                        SPAILog.debug(.camera, "head settling (\(String(format: "%.2f", stableDuration))s / \(DetectionTuning.headYawStableSeconds)s) — skipping frame")
                        continue
                    }
                } else {
                    // First yaw reading this session — establish the reference position.
                    stableReferenceYaw = currentYaw
                    stableFrom = now
                    SPAILog.debug(.camera, "head stability reference established at \(String(format: "%.2f", currentYaw)) rad")
                    continue
                }
            }

            // ── Zone crop + conversion ─────────────────────────────────────────────────
            //
            // Crop to the central passthrough rectangle before handing the image to
            // detection. CIImage.cropped(to:) is lazy — pixels outside the rect are never
            // rendered, so this is cheaper than cropping a fully-decoded UIImage.
            guard let image = UIImage.fromZoneCropped(readOnlyBuffer: sample.buffer) else { continue }
            lastDetectionTime = now
            SPAILog.debug(.camera, "frame sent to detection (zone \(Int(image.size.width))×\(Int(image.size.height)))")
            onFrameForDetection?(image)
        }

        isRunning = false
    }

    func stop() {
        arkitSession.stop()
        isRunning = false
        latestBuffer = nil
        stableReferenceYaw = nil
        stableFrom = nil
    }

    // MARK: - Helpers

    /// Shortest signed angular distance between two angles (radians), in (−π, π].
    private func wrappedAngleDelta(_ a: Float, _ b: Float) -> Float {
        var delta = a - b
        // fmod approach keeps this branchless for the common "already in range" case.
        delta = delta.truncatingRemainder(dividingBy: 2 * .pi)
        if delta >  .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }
}
