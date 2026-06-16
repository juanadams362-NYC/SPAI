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
    }

    /// Complete the current step and advance to the next legal step.
    func completeStep() {
        guard currentStepIndex < SterileStep.allCases.count - 1 else { return }
        currentStepIndex += 1
        stepStarted = false
    }

    /// Fail the current step — sends the tray back to decontamination.
    func failStep() {
        currentStepIndex = 0
        stepStarted = false
    }

    /// Trainee-only: redo the current step from scratch.
    func redoStep() {
        stepStarted = false
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
}
