//
//  DetectionService.swift
//  SPAI
//
//  Created by Juan Adams on 6/17/26.
//

//
//  DetectionService.swift
//  SPAI
//
//  Bridges the backend /detect endpoint to the UI. Holds the latest
//  result, exposes a derived contamination risk + PPE status, and lets
//  the sim send an image for inference. Environment readings are NOT from
//  the model — they stay mock until real sensors are wired.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class DetectionService {
    private let client = BackendClient()

    /// Latest tray state from /detect-tray. Nil until a tray-capable
    /// result arrives.
    var trayState: String?
    /// Latest instrument count reported by /detect-tray.
    var instrumentCount: Int?

    // --- Live state, fed from the backend ---
    /// Latest raw detections from /detect.
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

    /// Send an image to the backend and update state with the result.
    func detect(image: UIImage) async {
        isLoading = true
        errorMessage = nil
        trayState = nil
        instrumentCount = nil
        do {
            // Prefer the tray-aware endpoint so we can surface loaded/empty.
            // If the backend doesn't support it, fall back to plain detect.
            do {
                let tray = try await client.detectTray(image: image)
                detections = tray.detections
                trayState = tray.trayState
                instrumentCount = tray.instrumentCount
                hasResult = true
                print("[DetectionService] tray: state=\(tray.trayState), instruments=\(tray.instrumentCount), \(tray.detections.count) detections, \(tray.inferenceTimeMs)ms, mode=\(tray.mode)")
            } catch {
                let response = try await client.detect(image: image)
                detections = response.detections
                hasResult = true
                print("[DetectionService] (fallback) \(response.detections.count) detections, \(response.inferenceTimeMs)ms, mode=\(response.mode)")
            }
        } catch {
            errorMessage = "Detection failed: \(error.localizedDescription)"
            print("[DetectionService] error: \(error)")
        }
        isLoading = false
    }
}
