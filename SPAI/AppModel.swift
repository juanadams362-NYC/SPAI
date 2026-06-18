//
//  AppModel.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

enum PanelMode: String, CaseIterable, Identifiable {
    case fixed
    case followLazy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed:      return "Pinned"
        case .followLazy: return "Follows Me"
        }
    }
}

enum TechRole: String, CaseIterable, Identifiable {
    case technician = "Technician"
    case supervisor = "Supervisor"
    case trainee    = "Trainee"
    case observer   = "Observer"

    var id: String { rawValue }
}

enum SterileStep: Int, CaseIterable, Identifiable {
    case decontamination
    case inspection
    case trayAssembly
    case packaging
    case sealValidation

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .decontamination: return "Decontamination"
        case .inspection:      return "Inspection"
        case .trayAssembly:    return "Tray Assembly"
        case .packaging:       return "Packaging"
        case .sealValidation:  return "Seal Validation"
        }
    }

    /// The backend FSM's string name for this step.
    var backendName: String {
        switch self {
        case .decontamination: return "decontamination"
        case .inspection:      return "inspection"
        case .trayAssembly:    return "tray_assembly"
        case .packaging:       return "packaging"
        case .sealValidation:  return "seal_validation"
        }
    }
}

struct LogEvent: Identifiable {
    let id = UUID()
    let timestamp: String
    let message: String
    let kind: Kind

    enum Kind {
        case info, success, warning

        var color: Color {
            switch self {
            case .info:    return SPAIColor.accent
            case .success: return SPAIColor.safe
            case .warning: return SPAIColor.warning
            }
        }

        var icon: String {
            switch self {
            case .info:    return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }
}

@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "SPAIImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    private let onboardingKey = "hasCompletedOnboarding"
    private let client = BackendClient()

    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }

    var role: TechRole = .technician

    var panelModes: [String: PanelMode] = [:]
    func mode(for panelID: String) -> PanelMode { panelModes[panelID] ?? .fixed }
    func setMode(_ mode: PanelMode, for panelID: String) { panelModes[panelID] = mode }

    // MARK: - Panel appearance
    var panelVisibility: [String: Bool] = [:]
    /// Global panel opacity 0.5...1.0, driven by the Settings slider.
    /// Panels read this live so dragging the slider previews instantly.
    var panelOpacity: Double = 0.85
    func isVisible(_ panelID: String) -> Bool { panelVisibility[panelID] ?? true }
    func toggleVisibility(_ panelID: String) { panelVisibility[panelID] = !isVisible(panelID) }
    func showAllPanels() { panelVisibility.removeAll() }

    // MARK: - Event log

    var eventLog: [LogEvent] = []

    private func log(_ message: String, kind: LogEvent.Kind) {
        let time = Date().formatted(date: .omitted, time: .standard)
        eventLog.insert(LogEvent(timestamp: time, message: message, kind: kind), at: 0)
    }
    
    /// Log that the user walked to a station (called by StationManager.onEnter).
    func logStationEntry(_ name: String, step: SterileStep) {
        log("Entered \(name) station", kind: .info)
    }

    // MARK: - Workflow state

    var currentStepIndex: Int = 0
    var stepStarted: Bool = false

    var currentStep: SterileStep { SterileStep.allCases[currentStepIndex] }

    /// Start the current step — validated by the backend FSM.
    func startStep() {
        let step = currentStep
        stepStarted = true
        log("Started \(step.title)", kind: .info)
        Task {
            let result = try? await client.sendComplianceEvent("start_step", step: step.backendName)
            if let result, !result.accepted {
                log("Backend rejected start: \(result.message)", kind: .warning)
            }
        }
    }

    /// Complete the current step — validated by the backend FSM before advancing.
    func completeStep() {
        let completed = currentStep
        Task {
            let result = try? await client.sendComplianceEvent("complete_step", step: completed.backendName)
            await MainActor.run {
                if let result, !result.accepted {
                    // Backend says no — don't advance, surface why.
                    log("Backend rejected complete: \(result.message)", kind: .warning)
                    return
                }
                // Accepted (or backend unreachable) — advance locally.
                if currentStepIndex < SterileStep.allCases.count - 1 {
                    currentStepIndex += 1
                    log("Completed \(completed.title)", kind: .success)
                } else {
                    log("Completed \(completed.title) — workflow complete", kind: .success)
                }
                stepStarted = false
            }
        }
    }

    /// Fail the current step — contamination event to the FSM, tray back to decon.
    func failStep() {
        let failed = currentStep
        currentStepIndex = 0
        stepStarted = false
        log("Failed \(failed.title) — tray sent back to Decontamination", kind: .warning)
        Task {
            _ = try? await client.sendComplianceEvent("contamination")
        }
    }

    func redoStep() {
        let step = currentStep
        stepStarted = false
        log("Redo \(step.title)", kind: .info)
    }

    /// Reset both local state and the backend FSM.
    func resetWorkflow() {
        currentStepIndex = 0
        stepStarted = false
        eventLog.removeAll()
        log("Session started", kind: .info)
        Task { _ = try? await client.resetCompliance() }
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        log("Session started", kind: .info)
    }
}
