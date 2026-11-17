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
    
    private let instrumentSteps: Set<SterileStep> = [.decontamination, .inspection, .trayAssembly]
    
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
    
    func detect(image: UIImage, step: SterileStep?, preferOnDevice: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        trayState = nil
        instrumentCount = nil
        
        let wantInstruments = step.map { instrumentSteps.contains($0) } ?? false
        let wantTrayVerdict = (step == .trayAssembly)

        if preferOnDevice, onDevice.isAvailable {
            let local = await detectOnDevice(image: image, wantInstruments: wantInstruments, wantTrayVerdict: wantTrayVerdict)
            applyResult(local, mode: .onDevice)
            print("[DetectionService] on-device preferred: \(local.count) detections")
            return
        }
        
        do {
            async let ppeTask = client.detect(image: image)
            async let trayTask: TrayDetectResponse? = wantInstruments
                ? client.detectTray(image: image)
                : nil
            
            let ppe = try await ppeTask
            var merged = Self.resolvePPEOverlaps(ppe.detections.filter { Self.isPPEClass($0.className) })
            
            if let tray = try await trayTask {
                merged += tray.detections
                if wantTrayVerdict {
                    trayState = tray.trayState
                    instrumentCount = tray.instrumentCount
                }
            }
            
            applyResult(merged, mode: .cloud)
            print("[DetectionService] cloud: step=\(step?.title ?? "none"), \(merged.count) detections, \(ppe.inferenceTimeMs)ms")
        } catch {
            print("[DetectionService] cloud failed (\(error.localizedDescription)) — trying on-device")
            
            if onDevice.isAvailable {
                let local = await detectOnDevice(image: image, wantInstruments: wantInstruments, wantTrayVerdict: wantTrayVerdict)
                applyResult(local, mode: .onDevice)
                print("[DetectionService] on-device: \(local.count) detections")
            } else {
                mode = .offline
                errorMessage = "Detection unavailable — no backend and no on-device model."
                print("[DetectionService] fully offline")
            }
        }
    }

    private func detectOnDevice(
        image: UIImage,
        wantInstruments: Bool,
        wantTrayVerdict: Bool
    ) async -> [BackendDetection] {
        // Candidates arrive from a lower confidence so duplicate glove/hand labels can be
        // arbitrated before the on-device reporting threshold is applied.
        let candidates = await onDevice.detect(image: image)
        var local = Self.resolvePPEOverlaps(candidates.filter { Self.isPPEClass($0.className) })
            .filter { $0.confidence >= Self.onDevicePPEThreshold }

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

    private func applyResult(_ newDetections: [BackendDetection], mode newMode: DetectionMode) {
        detections = newDetections
        hasResult = true
        mode = newMode
        resultRevision += 1
    }

    // MARK: - PPE arbitration

    /// Minimum confidence for an on-device glove/hand detection to count.
    static let onDevicePPEThreshold: Double = 0.5

    /// The PPE model often labels one physical hand twice — "glove" and "hand" on the same
    /// spot — or adds a faint "glove" ghost over a bare hand. Per-class NMS can't catch that,
    /// so a gloved user read as "PPE check failed" and a ghost glove could mask a bare hand.
    /// Give each region its single most confident label. Mirrors `resolve_overlaps` in the
    /// backend so cloud and on-device detection agree.
    static func resolvePPEOverlaps(_ detections: [BackendDetection]) -> [BackendDetection] {
        var kept: [BackendDetection] = []
        for candidate in detections.sorted(by: { $0.confidence > $1.confidence }) {
            if !kept.contains(where: { boxesConflict(candidate.box, $0.box) }) {
                kept.append(candidate)
            }
        }
        return kept
    }

    /// True when two [x1, y1, x2, y2] boxes cover the same object: IoU ≥ 0.5, or at least
    /// 60% of the smaller box sits inside the larger one.
    static func boxesConflict(_ a: [Int], _ b: [Int]) -> Bool {
        guard a.count == 4, b.count == 4 else { return false }
        let ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
        let iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
        let intersection = Double(ix * iy)
        guard intersection > 0 else { return false }
        let areaA = Double(max(0, a[2] - a[0]) * max(0, a[3] - a[1]))
        let areaB = Double(max(0, b[2] - b[0]) * max(0, b[3] - b[1]))
        let union = areaA + areaB - intersection
        let iou = union > 0 ? intersection / union : 0
        let containment = intersection / max(1, min(areaA, areaB))
        return iou >= 0.5 || containment >= 0.6
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

