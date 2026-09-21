//
//  DetectionService.swift
//  SPAI
//

import SwiftUI
import UIKit

enum DetectionMode: String {
    case cloud = "Cloud"
    case onDevice = "On-Device"
    case offline = "Offline"
}

@MainActor
@Observable
final class DetectionService {
    private let client = BackendClient()
    private let onDevice = OnDeviceDetector()
    
    var mode: DetectionMode = .cloud
    
    var trayState: String?
    var instrumentCount: Int?
    
    var detections: [BackendDetection] = []
    var isLoading = false
    var errorMessage: String?
    var hasResult = false
    var resultRevision = 0

    var hasInstrumentDetection: Bool {
        detections.contains { Self.isInstrumentClass($0.className) }
    }
    
    /// True once a high-risk frame has been seen, and held until several consecutive frames
    /// disagree. See `DetectionTuning.clearFrameCount` for why this is one-directional.
    private var highRiskLatched = false
    private var clearStreak = 0

    /// Risk implied by the current frame alone, with no smoothing.
    private var frameRisk: Double {
        guard hasResult else { return 0 }
        let hasHand = detections.contains { Self.isHandClass($0.className) }
        let hasGlove = detections.contains { Self.isGloveClass($0.className) }
        if hasHand && !hasGlove { return 0.85 }
        if hasGlove { return 0.10 }
        return 0
    }

    /// Escalates immediately, clears only after `clearFrameCount` consecutive clean frames.
    private func updateStability() {
        if frameRisk >= 0.5 {
            highRiskLatched = true
            clearStreak = 0
        } else if highRiskLatched {
            clearStreak += 1
            if clearStreak >= DetectionTuning.clearFrameCount {
                highRiskLatched = false
                clearStreak = 0
            }
        }
    }

    var contaminationRisk: Double {
        guard hasResult else { return 0 }
        let frame = frameRisk
        // A bare hand raises the alarm on the frame it appears — never wait to warn.
        if frame >= 0.5 { return frame }
        // Once raised, hold it until enough frames agree it is over, so one occluded frame
        // cannot silently cancel a live contamination alert.
        if highRiskLatched { return 0.85 }
        return frame
    }

    var ppePassing: Bool {
        guard hasResult else { return false }
        let hasHand = detections.contains { Self.isHandClass($0.className) }
        let hasGlove = detections.contains { Self.isGloveClass($0.className) }
        return hasGlove && !hasHand && !highRiskLatched
    }
    
    /// Detects against a one-off image — a picked photo, a dropped file.
    ///
    /// Separate from `detect` because a still image is a *new subject*, not the next frame of
    /// the current one. The held contamination alert must not carry across: showing a bare-hand
    /// photo and then a gloved one would otherwise keep the alert up for three more detections,
    /// which looks like the app ignoring the new image.
    func detectStill(image: UIImage, step: SterileStep?, preferOnDevice: Bool = false) async {
        resetStability()
        await detect(image: image, step: step, preferOnDevice: preferOnDevice)
    }

    /// - Parameters:
    ///   - image: The frame or still image to run detection on.
    ///   - step: The active `SterileStep`, used as a coarse gate and to decide tray verdict.
    ///   - guidedCondition: When provided (live-camera path), gates inference to exactly what
    ///     the **current guided sub-step** requires. A `.manual` condition skips all inference.
    ///     When nil (upload / video path), the coarser step-level gate applies instead.
    func detect(image: UIImage, step: SterileStep?, guidedCondition: StepCondition? = nil, preferOnDevice: Bool = false) async {
        let wantPPE: Bool
        let wantInstruments: Bool

        if let condition = guidedCondition {
            // Sub-step gate: only run what this specific guided step needs.
            // .manual → both false → full early-out, zero inference.
            wantPPE = (condition == .glovesOn)
            wantInstruments = (condition == .instrumentsPresent || condition == .trayLoaded)
        } else {
            // Step-level fallback: used by still-image / video upload (no guided context).
            // nil step defaults to PPE-only so an unknown context is never completely blind.
            wantPPE = step?.needsPPEDetection ?? true
            wantInstruments = step?.needsInstrumentDetection ?? false
        }

        let wantTrayVerdict = wantInstruments && (step == .trayAssembly)

        guard wantPPE || wantInstruments else {
            SPAILog.debug(.detection, "skipping — step \(step?.title ?? "none") condition \(guidedCondition.map(String.init(describing:)) ?? "nil") needs no inference")
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        lastPathNote = nil
        trayState = nil
        instrumentCount = nil

        if preferOnDevice, onDevice.isAvailable {
            let local = await detectOnDevice(image: image, wantPPE: wantPPE, wantInstruments: wantInstruments, wantTrayVerdict: wantTrayVerdict)
            applyResult(local, mode: .onDevice)
            SPAILog.debug(.detection, "on-device preferred: \(local.count) detections")
            return
        }
        
        do {
            // Skip the PPE network call entirely when the step doesn't require it.
            async let ppeTask: DetectResponse? = wantPPE ? client.detect(image: image) : nil
            async let trayTask: TrayDetectResponse? = wantInstruments
                ? client.detectTray(image: image)
                : nil
            
            let ppe = try await ppeTask
            let tray = try await trayTask

            var merged: [BackendDetection] = []
            if let ppe { merged = ppe.detections.filter { Self.isPPEClass($0.className) } }
            if let tray { merged += tray.detections }

            // Same acceptance rules as the on-device path. The backend applies its own
            // confidence threshold, but it does not reject a chair-sized "instrument", and the
            // two paths must agree or the app behaves differently depending on whether the
            // backend happened to be reachable.
            let pixelSize = image.pixelSize
            let before = merged.count
            merged = Self.filterImplausible(
                merged,
                imageWidth: pixelSize.width,
                imageHeight: pixelSize.height
            )

            if wantTrayVerdict {
                // Recount from the filtered set rather than trusting the backend's raw count,
                // or a rejected chair still reads as a loaded tray.
                let instruments = merged.filter { Self.isInstrumentClass($0.className) }
                instrumentCount = instruments.count
                trayState = instruments.isEmpty ? "empty" : "loaded"
            }

            applyResult(merged, mode: .cloud)
            SPAILog.debug(.detection, "cloud: step=\(step?.title ?? "none"), kept \(merged.count)/\(before), PPE:\(ppe?.inferenceTimeMs ?? 0)ms")
        } catch {
            SPAILog.error(.detection, "cloud failed (\(error.localizedDescription)) — trying on-device")

            if onDevice.isAvailable {
                let local = await detectOnDevice(image: image, wantPPE: wantPPE, wantInstruments: wantInstruments, wantTrayVerdict: wantTrayVerdict)
                applyResult(local, mode: .onDevice)
                // Say *why* we fell back. Silently switching model and threshold because a URL
                // has a typo is exactly how the same build behaves differently on two machines.
                lastPathNote = "Backend unreachable — using the on-device model. \(error.localizedDescription)"
                errorMessage = "Can't reach the backend, so SPAI is using the on-device model. Check the Backend URL in Settings."
                SPAILog.debug(.detection, "on-device fallback: \(local.count) detections")
            } else {
                mode = .offline
                lastPathNote = "No backend and no on-device model."
                errorMessage = "Detection unavailable — no backend and no on-device model."
                SPAILog.info(.detection, "fully offline")
            }
        }
    }

    private func detectOnDevice(
        image: UIImage,
        wantPPE: Bool,
        wantInstruments: Bool,
        wantTrayVerdict: Bool
    ) async -> [BackendDetection] {
        var local: [BackendDetection] = []

        if wantPPE {
            local = await onDevice.detect(image: image)
                .filter { Self.isPPEClass($0.className) }
        }

        if wantInstruments && onDevice.hasInstruments {
            let instruments = await onDevice.detectInstruments(image: image)
            local += instruments
            if wantTrayVerdict {
                instrumentCount = instruments.count
                trayState = instruments.isEmpty ? "empty" : "loaded"
            }
        }

        return local
    }

    /// Which detection path last produced a result, and why — surfaced so a machine that is
    /// silently running on-device because its backend URL is wrong is diagnosable rather than
    /// just "iffy".
    private(set) var lastPathNote: String?

    private func applyResult(_ newDetections: [BackendDetection], mode newMode: DetectionMode) {
        detections = newDetections
        hasResult = true
        mode = newMode
        updateStability()
        resultRevision += 1
    }

    /// Clears the held alert. Called when the input source changes, so a contamination alert
    /// from a previous image can't carry over onto an unrelated new one.
    func resetStability() {
        highRiskLatched = false
        clearStreak = 0
    }

    static func isPPEClass(_ className: String) -> Bool {
        isGloveClass(className) || isHandClass(className)
    }

    static func isGloveClass(_ className: String) -> Bool {
        normalized(className).contains("glove")
    }

    static func isHandClass(_ className: String) -> Bool {
        let name = normalized(className)
        return name == "hand" || name.contains("barehand") || name.contains("bare_hand")
    }

    /// Only labels the instrument model actually produces count as instruments.
    ///
    /// This used to be `!isPPEClass(className)` — "anything that isn't a glove or a hand". That
    /// is why a chair could satisfy an instrument step: the detector forces every input into one
    /// of its six trained classes, and whatever came back was, by definition, an instrument.
    /// An allow-list means an unexpected label is ignored rather than trusted.
    static func isInstrumentClass(_ className: String) -> Bool {
        guard !isPPEClass(className) else { return false }
        return DetectionTuning.isInstrumentLabel(className)
    }

    private static func normalized(_ className: String) -> String {
        DetectionTuning.normalized(className)
    }

    /// Drops detections that are the wrong confidence or an implausible size for what they
    /// claim to be. Applied to cloud results as well as on-device ones, so both paths agree.
    static func filterImplausible(
        _ detections: [BackendDetection],
        imageWidth: Int,
        imageHeight: Int
    ) -> [BackendDetection] {
        detections.filter { detection in
            let instrument = isInstrumentClass(detection.className)
            let floor = instrument ? DetectionTuning.instrumentConfidence : DetectionTuning.ppeConfidence
            guard detection.confidence >= floor else { return false }
            guard isPPEClass(detection.className) || instrument else { return false }
            return DetectionTuning.isPlausible(
                box: detection.box,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                isInstrument: instrument
            )
        }
    }
}

