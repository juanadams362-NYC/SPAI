//
//  DetectionService.swift
//  SPAI
//
//  Bridges the backend detection endpoints to the UI. Holds the latest
//  result, exposes a derived contamination risk + PPE status, and lets
//  the sim send an image for inference.
//
//  Routing rule lives HERE, not in views: glove/hand detection runs on
//  every step, everywhere. Tray detection only runs on the Tray Assembly
//  step, layered on top of PPE — never instead of it. Views just pass in
//  the current step and the service decides what to call.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class DetectionService {
    private let client = BackendClient()

    /// Latest tray state from /detect-tray. Nil unless the last run was
    /// on the Tray Assembly step — the UI uses nil to hide tray output.
    var trayState: String?
    /// Latest instrument count reported by /detect-tray.
    var instrumentCount: Int?

    // --- Live state, fed from the backend ---
    /// Latest detections. On tray assembly this is PPE + instruments merged.
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
    /// PPE always runs. Tray runs only on .trayAssembly, in parallel,
    /// and its instruments get merged into the same detections list.
    func detect(image: UIImage, step: SterileStep?) async {
        isLoading = true
        errorMessage = nil
        trayState = nil
        instrumentCount = nil

        let wantTray = (step == .trayAssembly)

        do {
            // async let starts both requests at the same time instead of
            // one after the other — the wait is max(a, b), not a + b.
            async let ppeTask = client.detect(image: image)
            async let trayTask: TrayDetectResponse? = wantTray
                ? client.detectTray(image: image)
                : nil

            let ppe = try await ppeTask
            var merged = ppe.detections

            if let tray = try await trayTask {
                merged += tray.detections
                trayState = tray.trayState
                instrumentCount = tray.instrumentCount
                print("[DetectionService] tray: state=\(tray.trayState), instruments=\(tray.instrumentCount)")
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
