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
    // Reading pulls from disk; writing saves to disk immediately.
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

    init() {
        // Load the saved onboarding state at startup (defaults to false).
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
}
