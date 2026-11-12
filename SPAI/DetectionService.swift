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

    // MARK: - Instrument identification

    /// The instrument currently confirmed in frame — what the user is
    /// holding up. Nil when no instrument has been steadily visible.
    private(set) var identifiedInstrument: IdentifiedInstrument?

    /// The most recent instrument worth telling the user about. Changes only
    /// when a new instrument is confirmed, not on every frame.
    private(set) var announcedInstrument: IdentifiedInstrument?

    /// Bumps each time `announcedInstrument` should be spoken / shown, so
    /// views can react with `onChange` even if the same instrument is shown
    /// twice in a row.
    private(set) var announcementRevision = 0

    private var tracker = InstrumentTracker()

    /// Nil until we've tried. False once the backend has told us it has no
    /// /analyze route, after which we stop asking and use the older pair of
    /// endpoints for the rest of the session.
    private var backendSupportsAnalyze: Bool?

    var hasInstrumentDetection: Bool {
        detections.contains { Self.isInstrumentClass($0.className) }
    }

    /// Display names of every instrument in the current frame.
    var instrumentNames: [String] {
        detections
            .filter { Self.isInstrumentClass($0.className) }
            .map { InstrumentCatalog.displayName(for: $0.className) }
    }

    var contaminationRisk: Double {
        guard hasResult else { return 0 }
        let hasHand = detections.contains { Self.isHandClass($0.className) }
        let hasGlove = detections.contains { Self.isGloveClass($0.className) }
        if hasHand && !hasGlove { return 0.85 }
        if hasGlove { return 0.10 }
        return 0
    }

    var ppePassing: Bool {
        let hasHand = detections.contains { Self.isHandClass($0.className) }
        let hasGlove = detections.contains { Self.isGloveClass($0.className) }
        return hasGlove && !hasHand
    }

    /// Runs detection on one frame.
    ///
    /// Instruments are looked for on every frame, at every station, so the
    /// user can hold one up and ask "what is this?" at any point. The
    /// loaded/empty tray verdict is still only reported during Tray Assembly,
    /// the one station where it means something.
    func detect(image: UIImage, step: SterileStep?, preferOnDevice: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        trayState = nil
        instrumentCount = nil

        let wantTrayVerdict = (step == .trayAssembly)

        if preferOnDevice, onDevice.isAvailable {
            let local = await detectOnDevice(image: image, wantTrayVerdict: wantTrayVerdict)
            applyResult(local, mode: .onDevice)
            print("[DetectionService] on-device preferred: \(local.count) detections")
            return
        }

        do {
            let merged = try await detectInCloud(image: image, wantTrayVerdict: wantTrayVerdict)
            applyResult(merged, mode: .cloud)
            print("[DetectionService] cloud: step=\(step?.title ?? "none"), \(merged.count) detections")
        } catch {
            print("[DetectionService] cloud failed (\(error.localizedDescription)) — trying on-device")

            if onDevice.isAvailable {
                let local = await detectOnDevice(image: image, wantTrayVerdict: wantTrayVerdict)
                applyResult(local, mode: .onDevice)
                print("[DetectionService] on-device: \(local.count) detections")
            } else {
                mode = .offline
                errorMessage = "Detection unavailable — no backend and no on-device model."
                print("[DetectionService] fully offline")
            }
        }
    }

    /// One upload to /analyze when the backend has it; otherwise the older
    /// /detect + /detect-tray pair.
    private func detectInCloud(image: UIImage, wantTrayVerdict: Bool) async throws -> [BackendDetection] {
        if backendSupportsAnalyze != false {
            do {
                let analysis = try await client.analyze(image: image)
                backendSupportsAnalyze = true
                if wantTrayVerdict {
                    trayState = analysis.trayState
                    instrumentCount = analysis.instrumentCount
                }
                return analysis.detections.filter { Self.isPPEClass($0.className) } + analysis.instruments
            } catch BackendError.endpointMissing {
                backendSupportsAnalyze = false
                print("[DetectionService] backend has no /analyze — using /detect + /detect-tray")
            }
        }

        async let ppeTask = client.detect(image: image)
        async let trayTask = client.detectTray(image: image)

        let ppe = try await ppeTask
        let tray = try await trayTask

        if wantTrayVerdict {
            trayState = tray.trayState
            instrumentCount = tray.instrumentCount
        }
        return ppe.detections.filter { Self.isPPEClass($0.className) } + tray.detections
    }

    private func detectOnDevice(image: UIImage, wantTrayVerdict: Bool) async -> [BackendDetection] {
        var local = await onDevice.detect(image: image)
            .filter { Self.isPPEClass($0.className) }

        if onDevice.hasInstruments {
            let instruments = await onDevice.detectInstruments(image: image)
            local += instruments
            if wantTrayVerdict {
                instrumentCount = instruments.count
                trayState = instruments.isEmpty ? "empty" : "loaded"
            }
        }

        return local
    }

    private func applyResult(_ newDetections: [BackendDetection], mode newMode: DetectionMode) {
        detections = newDetections
        hasResult = true
        mode = newMode
        resultRevision += 1
        updateIdentification()
    }

    /// Folds this frame into the running identification. A new instrument is
    /// only surfaced once it has been seen steadily, so one flickering box
    /// never triggers an announcement.
    private func updateIdentification() {
        let candidate = InstrumentIdentifier.identify(in: detections)
        if let announcement = tracker.ingest(candidate) {
            announcedInstrument = announcement
            announcementRevision += 1
        }
        if identifiedInstrument != tracker.current {
            identifiedInstrument = tracker.current
        }
    }

    /// Forgets what was in frame — used when the session is reset so the
    /// next instrument shown is announced fresh.
    func resetIdentification() {
        tracker.reset()
        identifiedInstrument = nil
        announcedInstrument = nil
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

    static func isInstrumentClass(_ className: String) -> Bool {
        !isPPEClass(className)
    }

    private static func normalized(_ className: String) -> String {
        className
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
