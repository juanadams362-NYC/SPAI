//
//  DetectionService.swift
//  SPAI
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class DetectionService {
    private let client = BackendClient()

    private let instrumentSteps: Set<SterileStep> = [.decontamination, .inspection, .trayAssembly]

    var trayState: String?
    var instrumentCount: Int?

    var detections: [BackendDetection] = []
    var isLoading = false
    var errorMessage: String?
    var hasResult = false

    var contaminationRisk: Double {
        guard hasResult else { return 0 }
        let hasHand = detections.contains { $0.className.lowercased() == "hand" }
        let hasGlove = detections.contains { $0.className.lowercased() == "glove" }
        if hasHand && !hasGlove { return 0.85 }
        if hasGlove { return 0.10 }
        return 0
    }

    var ppePassing: Bool {
        let hasHand = detections.contains { $0.className.lowercased() == "hand" }
        let hasGlove = detections.contains { $0.className.lowercased() == "glove" }
        return hasGlove && !hasHand
    }

    func detect(image: UIImage, step: SterileStep?) async {
        isLoading = true
        errorMessage = nil
        trayState = nil
        instrumentCount = nil

        let wantInstruments = step.map { instrumentSteps.contains($0) } ?? false
        let wantTrayVerdict = (step == .trayAssembly)

        do {
            async let ppeTask = client.detect(image: image)
            async let trayTask: TrayDetectResponse? = wantInstruments
                ? client.detectTray(image: image)
                : nil

            let ppe = try await ppeTask
            var merged = ppe.detections

            if let tray = try await trayTask {
                merged += tray.detections
                if wantTrayVerdict {
                    trayState = tray.trayState
                    instrumentCount = tray.instrumentCount
                }
                print("[DetectionService] instruments: \(tray.detections.count) found, verdict shown: \(wantTrayVerdict)")
            }

            detections = merged
            hasResult = true
            print("[DetectionService] step=\(step?.title ?? "none"), \(merged.count) detections, \(ppe.inferenceTimeMs)ms, mode=\(ppe.mode)")
        } catch {
            errorMessage = "Detection failed: \(error.localizedDescription)"
            print("[DetectionService] error: \(error)")
        }
        isLoading = false
    }
}
