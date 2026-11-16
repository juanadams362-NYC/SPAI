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

    /// When the last camera frame arrived, from any source. Lets the UI
    /// tell "no camera" apart from "camera running, nothing in view".
    private(set) var lastFrameAt: Date?

    /// True when on-device models are loaded, so private mode can be honoured.
    var canRunOnDevice: Bool { onDevice.isAvailable }

    /// The user's choice in Settings. On unless they have turned it off.
    static var keepsFramesOnDevice: Bool {
        UserDefaults.standard.object(forKey: "detectOnDevice") as? Bool ?? true
    }

    /// How many of each instrument are in view, by catalog key. Takes the
    /// highest count over the last few frames, so one dropped detection
    /// doesn't make an instrument blink out of the count sheet.
    private(set) var instrumentCounts: [String: Int] = [:]
    private var recentCounts: [[String: Int]] = []
    private static let countWindow = 4

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
        let hands = Self.resolveHands(detections)
        if hands.bare > 0 { return 0.85 }
        if hands.gloved > 0 { return 0.10 }
        return 0
    }

    var ppePassing: Bool {
        let hands = Self.resolveHands(detections)
        return hands.gloved > 0 && hands.bare == 0
    }

    /// Counts gloved and bare hands in a frame.
    ///
    /// The glove model often puts two boxes on one hand, one "glove" and one
    /// "hand", almost exactly on top of each other. The old rule ("any glove
    /// in view means safe") hid that, but also hid a genuinely bare hand
    /// next to a gloved one, which is exactly the contamination SPAI exists
    /// to catch. Here, boxes that overlap heavily are one hand, and the more
    /// confident label decides what it is. A tie goes to "glove", so an
    /// ambiguous frame doesn't halt the workflow by itself; a bare hand has
    /// to be seen clearly (confidence at least `bareHandConfidence`).
    static func resolveHands(_ detections: [BackendDetection]) -> (gloved: Int, bare: Int) {
        let candidates = detections
            .filter { isPPEClass($0.className) && $0.box.count == 4 }
            .sorted { $0.confidence > $1.confidence }
        var kept: [BackendDetection] = []
        for detection in candidates where !kept.contains(where: { iou($0.box, detection.box) >= sameHandOverlap }) {
            kept.append(detection)
        }
        // Same confidence, same place: prefer glove.
        let resolved = kept.map { winner -> BackendDetection in
            if isHandClass(winner.className),
               candidates.contains(where: { isGloveClass($0.className) && $0.confidence >= winner.confidence
                                            && iou($0.box, winner.box) >= sameHandOverlap }) {
                return BackendDetection(classId: 0, className: "glove", confidence: winner.confidence, box: winner.box)
            }
            return winner
        }
        let gloved = resolved.filter { isGloveClass($0.className) }.count
        let bare = resolved.filter { isHandClass($0.className) && $0.confidence >= bareHandConfidence }.count
        return (gloved, bare)
    }

    /// Boxes overlapping at least this much (intersection over union) are
    /// treated as the same hand.
    static let sameHandOverlap = 0.5
    /// A bare hand only counts when the model is at least this sure.
    static let bareHandConfidence = 0.5

    private static func iou(_ a: [Int], _ b: [Int]) -> Double {
        guard a.count == 4, b.count == 4 else { return 0 }
        let width = max(0, min(a[2], b[2]) - max(a[0], b[0]))
        let height = max(0, min(a[3], b[3]) - max(a[1], b[1]))
        let intersection = Double(width * height)
        let union = Double((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1])) - intersection
        return union > 0 ? intersection / union : 0
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
        lastFrameAt = Date()

        // Private mode: frames stay on the headset whenever the on-device
        // models can do the job. This is the default, and it is what the
        // privacy page tells an institution's IT office.
        let onDeviceFirst = preferOnDevice || Self.keepsFramesOnDevice

        errorMessage = nil
        trayState = nil
        instrumentCount = nil

        let wantTrayVerdict = (step == .trayAssembly)

        // Private mode is a promise, not a preference. If the on-device
        // model can't run, say so; never quietly send the frame instead.
        if Self.keepsFramesOnDevice, !onDevice.isAvailable {
            mode = .offline
            errorMessage = "On-headset checks aren't available on this device. To use the server instead, turn off \"Keep camera frames on this headset\" in Settings."
            return
        }

        if onDeviceFirst, onDevice.isAvailable {
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
        updateInstrumentCounts()
    }

    private func updateInstrumentCounts() {
        var frame: [String: Int] = [:]
        for detection in detections where Self.isInstrumentClass(detection.className) {
            // Only count instruments SPAI is prepared to name; a low-
            // confidence box shouldn't tick an item off a count sheet.
            guard detection.confidence >= InstrumentCatalog.identifyThreshold,
                  let info = InstrumentCatalog.lookup(detection.key ?? detection.className) else { continue }
            frame[info.key, default: 0] += 1
        }
        recentCounts.append(frame)
        if recentCounts.count > Self.countWindow { recentCounts.removeFirst() }

        var best: [String: Int] = [:]
        for counts in recentCounts {
            for (key, count) in counts { best[key] = max(best[key] ?? 0, count) }
        }
        if best != instrumentCounts { instrumentCounts = best }
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
        recentCounts = []
        instrumentCounts = [:]
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
