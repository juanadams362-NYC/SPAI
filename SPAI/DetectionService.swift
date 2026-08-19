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
            var merged = ppe.detections.filter { Self.isPPEClass($0.className) }
            
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
        var local = await onDevice.detect(image: image)
            .filter { Self.isPPEClass($0.className) }

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
