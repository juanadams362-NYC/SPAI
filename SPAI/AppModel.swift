//
//  AppModel.swift
//  SPAI
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
    let history = SessionHistory()

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

    var role: TechRole = .technician {
        didSet {
            guard role != oldValue else { return }
            log("Role changed to \(role.rawValue)", kind: .info)
            if role == .observer || role == .supervisor {
                panelVisibility["history"] = true
            }
            if isReadOnly && stepStarted {
                resetWorkflow()
            }
        }
    }

    // MARK: - Role permissions

    var canRunWorkflow: Bool { role == .technician || role == .trainee }
    var isReadOnly: Bool { role == .supervisor || role == .observer }

    var panelModes: [String: PanelMode] = [:]
    func mode(for panelID: String) -> PanelMode { panelModes[panelID] ?? .fixed }
    func setMode(_ mode: PanelMode, for panelID: String) { panelModes[panelID] = mode }

    // MARK: - Panel appearance
    var panelVisibility: [String: Bool] = ["chat": false, "history": false]
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

    func logStationEntry(_ name: String, step: SterileStep) {
        log("Entered \(name) station", kind: .info)
    }

    // MARK: - Workflow state

    var currentStepIndex: Int = 0
    var stepStarted: Bool = false
    var isHalted: Bool = false

    var sessionComplete: Bool = false
    var sessionStart: Date = Date()
    var contaminationCount: Int = 0
    var guidedStepIndex: Int = 0
    var currentStep: SterileStep { SterileStep.allCases[currentStepIndex] }

    func startStep() {
        guard canRunWorkflow else { return }
        let step = currentStep
        stepStarted = true
        guidedStepIndex = 0
        log("Started \(step.title)", kind: .info)
        Task {
            let result = try? await client.sendComplianceEvent("start_step", step: step.backendName)
            if let result, !result.accepted {
                await MainActor.run {
                    stepStarted = false
                    log("Backend rejected start: \(result.message)", kind: .warning)
                }
            }
        }
    }

    func completeStep() {
        guard canRunWorkflow else { return }
        let completed = currentStep
        Task {
            let result = try? await client.sendComplianceEvent("complete_step", step: completed.backendName)
            await MainActor.run {
                if let result, !result.accepted {
                    log("Backend rejected complete: \(result.message)", kind: .warning)
                    return
                }
                if currentStepIndex < SterileStep.allCases.count - 1 {
                    currentStepIndex += 1
                    log("Completed \(completed.title)", kind: .success)
                } else {
                    log("Completed \(completed.title) — workflow complete", kind: .success)
                    sessionComplete = true
                    history.add(SessionRecord(
                        passed: contaminationCount == 0,
                        contaminationCount: contaminationCount,
                        durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
                        events: eventLog.map { "\($0.timestamp)  \($0.message)" },
                        role: role.rawValue
                    ))
                }
                stepStarted = false
                guidedStepIndex = 0
            }
        }
    }

    func failStep() {
        guard canRunWorkflow else { return }
        let failed = currentStep
        currentStepIndex = 0
        stepStarted = false
        guidedStepIndex = 0
        isHalted = false
        log("Failed \(failed.title) — tray sent back to Decontamination", kind: .warning)
        Task { _ = try? await client.resetCompliance() }
    }

    func raiseContamination() {
        isHalted = true
        log("Contamination detected — workflow halted", kind: .warning)
        contaminationCount += 1
        Task { _ = try? await client.sendComplianceEvent("contamination") }
    }

    func acknowledgeContamination() {
        guard canRunWorkflow else { return }
        isHalted = false
        log("Contamination acknowledged — workflow resumed", kind: .info)
        Task { _ = try? await client.sendComplianceEvent("acknowledge") }
    }

    func redoStep() {
        guard canRunWorkflow else { return }
        let step = currentStep
        stepStarted = false
        guidedStepIndex = 0
        log("Redo \(step.title)", kind: .info)
    }

    func resetWorkflow() {
        currentStepIndex = 0
        stepStarted = false
        guidedStepIndex = 0
        isHalted = false
        eventLog.removeAll()
        log("Session reset", kind: .info)
        sessionComplete = false
        contaminationCount = 0
        sessionStart = Date()
        Task { _ = try? await client.resetCompliance() }
    }

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        Task { _ = try? await client.resetCompliance() }
        log("Session started", kind: .info)
    }
}
