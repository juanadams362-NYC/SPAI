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
    private let tourKey = "hasCompletedTour"
    private let client = BackendClient()

    /// The pre-launch welcome pages.
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        }
    }

    /// The in-app guided tour. Tracked separately from `hasCompletedOnboarding` because they
    /// answer different questions: the welcome pages say what SPAI is, the tour teaches the
    /// workspace. Finishing one should not silently suppress the other.
    var hasCompletedTour: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedTour, forKey: tourKey)
        }
    }

    let tour = AppTour()

    func completeTour() { hasCompletedTour = true }

    /// Replays the tour from Settings.
    func restartTour() {
        hasCompletedTour = false
        tour.start()
    }

    var role: TechRole = .technician {
        didSet {
            guard role != oldValue else { return }
            tour.note(.changedRole)
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
    var panelsBillboard: Bool = true  // Panels look at you when you move
    var isSettingsWindowOpen: Bool = false {
        didSet {
            guard isSettingsWindowOpen, !oldValue else { return }
            tour.note(.openedSettings)
        }
    }
    var isUploadWindowOpen: Bool = false
    
    func isVisible(_ panelID: String) -> Bool { panelVisibility[panelID] ?? true }
    func showAllPanels() { panelVisibility.removeAll() }

    /// Panel that most recently became visible, and when. `ImmersiveView` reads this to play
    /// the "fly in from the button you tapped" transition, so a panel that opens off to the
    /// side announces itself instead of silently appearing outside the user's field of view.
    var lastOpenedPanel: (id: String, at: Date)?

    func toggleVisibility(_ panelID: String) {
        let nowVisible = !isVisible(panelID)
        panelVisibility[panelID] = nowVisible
        guard nowVisible else { return }
        lastOpenedPanel = (panelID, Date())
        switch panelID {
        case "chat":    tour.note(.openedChat)
        case "history": tour.note(.openedHistory)
        case "upload":  tour.note(.openedUpload)
        default:        break
        }
    }

    // MARK: - Event log

    var eventLog: [LogEvent] = []

    private func log(_ message: String, kind: LogEvent.Kind) {
        let time = Date().formatted(date: .omitted, time: .standard)
        eventLog.insert(LogEvent(timestamp: time, message: message, kind: kind), at: 0)
    }

    func logStationEntry(_ name: String, step: SterileStep) {
        log("Entered \(name) station", kind: .info)
    }

    func logVideoDetectionTransition(_ state: String, at seconds: Double) {
        let timestamp = Self.videoTimestamp(seconds)
        let kind: LogEvent.Kind = state == "bare hand" ? .warning : .info
        log("Video: \(state) at \(timestamp)", kind: kind)
    }

    private static func videoTimestamp(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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

    var shouldHaltOnBareHand: Bool {
        guard stepStarted else { return false }
        let script = StationScripts.script(for: currentStep)
        let idx = min(max(guidedStepIndex, 0), script.count - 1)
        return script[idx].condition != .glovesOn
    }

    // MARK: - Guided step speech

    private func speakCurrentGuidedStep() {
        let script = StationScripts.script(for: currentStep)
        guard !script.isEmpty else { return }
        let idx = min(max(guidedStepIndex, 0), script.count - 1)
        SpeechManager.shared.speak(script[idx].instruction)
    }

    func advanceGuidedStep() {
        let script = StationScripts.script(for: currentStep)
        guard guidedStepIndex < script.count - 1 else { return }
        guidedStepIndex += 1
        speakCurrentGuidedStep()
    }

    func startStep() {
        guard canRunWorkflow else { return }
        let step = currentStep
        stepStarted = true
        guidedStepIndex = 0
        tour.note(.startedStep)
        log("Started \(step.title)", kind: .info)
        speakCurrentGuidedStep()
        Task {
            let result = try? await client.sendComplianceEvent("start_step", step: step.backendName)
            if let result, !result.accepted {
                await MainActor.run {
                    stepStarted = false
                    SpeechManager.shared.stop()
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
                SpeechManager.shared.stop()
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
        SpeechManager.shared.stop()
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
        SpeechManager.shared.stop()
        log("Redo \(step.title)", kind: .info)
    }

    func resetWorkflow() {
        SpeechManager.shared.stop()
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
        self.hasCompletedTour = UserDefaults.standard.bool(forKey: tourKey)
        Task { _ = try? await client.resetCompliance() }
        log("Session started", kind: .info)
    }
}
