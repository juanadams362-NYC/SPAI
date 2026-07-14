//
//  DetectionService.swift
//  SPAI
//
//  Bridges the backend detection endpoints to the UI. Holds the latest
//  result, exposes a derived contamination risk + PPE status, and lets
//  the sim send an image for inference.
//
//  Routing rule lives HERE, not in views: glove/hand detection runs on
//  every step, everywhere. The instrument model runs on every step that
//  handles instruments (decontam, inspection, tray assembly) so guided
//  gates and the AI can see them — but the tray loaded/empty VERDICT
//  is only surfaced on Tray Assembly, where it means something.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class DetectionService {
    private let client = BackendClient()

    /// Steps where instruments are physically in play, so the instrument
    /// model should run. Data for gates + AI context — not the same thing
    /// as showing the tray verdict UI.
    private let instrumentSteps: Set<SterileStep> = [.decontamination, .inspection, .trayAssembly]

    /// Tray verdict from /detect-tray. Only set on Tray Assembly — the
    /// UI uses nil to hide tray output everywhere else.
    var trayState: String?
    /// Instrument count for the tray verdict. Same rule: Tray Assembly only.
    var instrumentCount: Int?

    // --- Live state, fed from the backend ---
    /// Latest detections. Instruments merge in on instrument steps.
    var detections: [BackendDetection] = []
    /// True while a request is in flight (drives the loading state in the UI).
    var isLoading = false
    /// Set when a request fails, so the panel can show an error instead of hanging.
    var errorMessage: String?
    /// Whether we've received at least one response (so the panel knows real vs. idle).
    var hasResult = false

    // --- Derived values the panel reads ---

    /// Contamination risk 0...1, computed from detections.
    /// Rule: a bare hand (no glove) is the risk. Glove present = low risk.
    var contaminationRisk: Double {
        guard hasResult else { return 0 }
        let hasHand = detections.contains { $0.className.lowercased() == "hand" }
        let hasGlove = detections.contains { $0.className.lowercased() == "glove" }
        if hasHand && !hasGlove { return 0.85 }   // bare hand → high risk
        if hasGlove { return 0.10 }               // gloved → low risk
        return 0                                  // nothing detected → no signal
    }

    /// PPE passes when a glove is detected and no bare hand is showing.
    var ppePassing: Bool {
        let hasHand = detections.contains { $0.className.lowercased() == "hand" }
        let hasGlove = detections.contains { $0.className.lowercased() == "glove" }
        return hasGlove && !hasHand
    }

    /// Run detection for the given workflow step.
    /// PPE always runs. The instrument model runs on instrument steps,
    /// in parallel, and its detections merge into the same list. The
    /// tray verdict (state + count) is only kept on Tray Assembly.
    func detect(image: UIImage, step: SterileStep?) async {
        isLoading = true
        errorMessage = nil
        trayState = nil
        instrumentCount = nil

        let wantInstruments = step.map { instrumentSteps.contains($0) } ?? false
        let wantTrayVerdict = (step == .trayAssembly)

        do {
            // async let starts both requests at the same time instead of
            // one after the other — the wait is max(a, b), not a + b.
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
