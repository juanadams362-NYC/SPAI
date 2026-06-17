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

/// The five sterile-processing steps, in order. Lives here now so the
/// workflow panel, event log, and FSM all read the same step state.
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
}

/// One logged event in the activity feed. Owned by AppModel so the whole
/// app writes to and reads from one shared history (the seed of the
/// compliance audit trail).
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

    // Key under which the onboarding flag is stored on disk.
    private let onboardingKey = "hasCompletedOnboarding"

    // Backed by UserDefaults so onboarding only shows on first ever launch.
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }

    var role: TechRole = .technician

    var panelModes: [String: PanelMode] = [:]

    func mode(for panelID: String) -> PanelMode {
        panelModes[panelID] ?? .fixed
    }

    func setMode(_ mode: PanelMode, for panelID: String) {
        panelModes[panelID] = mode
    }

    var panelVisibility: [String: Bool] = [:]

    func isVisible(_ panelID: String) -> Bool {
        panelVisibility[panelID] ?? true
    }

    func toggleVisibility(_ panelID: String) {
        panelVisibility[panelID] = !isVisible(panelID)
    }

    func showAllPanels() {
        panelVisibility.removeAll()
    }

    // MARK: - Event log (shared activity history)

    /// Newest event first. The workflow methods below append to this, and
    /// EventLogPanel reads from it.
    var eventLog: [LogEvent] = []

    /// Append a timestamped event to the front of the log.
    private func log(_ message: String, kind: LogEvent.Kind) {
        let time = Date().formatted(date: .omitted, time: .standard)
        eventLog.insert(LogEvent(timestamp: time, message: message, kind: kind), at: 0)
    }

    // MARK: - Workflow state (single source of truth)

    /// Index of the step the user is currently on.
    var currentStepIndex: Int = 0
    /// Whether the current step has been started vs. just selected.
    var stepStarted: Bool = false

    var currentStep: SterileStep {
        SterileStep.allCases[currentStepIndex]
    }

    /// Begin the current step.
    func startStep() {
        stepStarted = true
        log("Started \(currentStep.title)", kind: .info)
    }

    /// Complete the current step and advance to the next legal step.
    func completeStep() {
        let completed = currentStep
        guard currentStepIndex < SterileStep.allCases.count - 1 else {
            // Last step completed — workflow finished.
            stepStarted = false
            log("Completed \(completed.title) — workflow complete", kind: .success)
            return
        }
        currentStepIndex += 1
        stepStarted = false
        log("Completed \(completed.title)", kind: .success)
    }

    /// Fail the current step — sends the tray back to decontamination.
    func failStep() {
        let failed = currentStep
        currentStepIndex = 0
        stepStarted = false
        log("Failed \(failed.title) — tray sent back to Decontamination", kind: .warning)
    }

    /// Trainee-only: redo the current step from scratch.
    func redoStep() {
        let step = currentStep
        stepStarted = false
        log("Redo \(step.title)", kind: .info)
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        log("Session started", kind: .info)
    }
}
