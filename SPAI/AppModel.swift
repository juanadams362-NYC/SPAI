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

/// How much of the workspace is on screen at once.
enum PanelLayout: String, CaseIterable, Identifiable {
    /// Only what the current task needs. Everything else stays one tap away.
    case focus
    /// Every panel open, for supervisors and demos.
    case everything

    var id: String { rawValue }
    var label: String {
        switch self {
        case .focus:      return "Focus"
        case .everything: return "Everything"
        }
    }
}

/// Stable ids for the panels in the immersive space. The same strings key
/// the RealityView attachments, panel visibility, and the guide's spotlight.
enum PanelID {
    static let statusBar = "statusBar"
    static let workflow = "workflow"
    static let detection = "detection"
    static let guided = "guided"
    static let report = "report"
    static let eventLog = "eventLog"
    static let history = "history"
    static let chat = "chat"
    static let upload = "upload"
    static let wristMenu = "wristMenu"
    static let stationPicker = "stationPicker"
    static let guideBubble = "guideBubble"

    /// Panels the user can open and close from the Panels menu.
    static let optional = [eventLog, history, chat, upload]

    static func title(_ id: String) -> String {
        switch id {
        case eventLog: return "Event Log"
        case history:  return "Session History"
        case chat:     return "Ask SPAI"
        case upload:   return "Test Media"
        default:       return id
        }
    }

    static func icon(_ id: String) -> String {
        switch id {
        case eventLog: return "waveform.path.ecg"
        case history:  return "clock.arrow.circlepath"
        case chat:     return "sparkles"
        case upload:   return "photo.badge.plus"
        default:       return "rectangle"
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
                panelVisibility[PanelID.history] = true
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

    /// Explicit show/hide choices the user has made. A panel with no entry
    /// here follows the current layout's default.
    var panelVisibility: [String: Bool] = [:]
    var panelOpacity: Double = 0.85
    var panelsBillboard: Bool = true  // Panels look at you when you move
    var isSettingsWindowOpen: Bool = false
    var isUploadWindowOpen: Bool = false

    private let layoutKey = "panelLayout"

    /// Focus by default: a first-time user sees three panels, not ten.
    var layout: PanelLayout {
        didSet {
            guard layout != oldValue else { return }
            UserDefaults.standard.set(layout.rawValue, forKey: layoutKey)
            // Switching layout is a fresh start — drop per-panel overrides so
            // the new layout looks the way its name promises.
            panelVisibility.removeAll()
        }
    }

    /// Whether a panel is open when the user hasn't said otherwise.
    private func defaultVisibility(_ panelID: String) -> Bool {
        switch panelID {
        case PanelID.statusBar, PanelID.workflow, PanelID.detection:
            return true
        case PanelID.eventLog, PanelID.upload:
            return layout == .everything
        default:
            // Chat and history open on demand in either layout.
            return false
        }
    }

    func isVisible(_ panelID: String) -> Bool {
        panelVisibility[panelID] ?? defaultVisibility(panelID)
    }

    /// Visible, or being pointed at by the guide right now — the guide can
    /// reveal a closed panel for as long as it is talking about it.
    func isShown(_ panelID: String) -> Bool {
        isVisible(panelID) || spotlightPanel == panelID
    }

    func toggleVisibility(_ panelID: String) { panelVisibility[panelID] = !isVisible(panelID) }
    func showAllPanels() { PanelID.optional.forEach { panelVisibility[$0] = true } }

    // MARK: - Guide companion

    private let companionKey = "showCompanion"
    private let spatialTourKey = "hasSeenSpatialTour"
    private let announceKey = "announceInstruments"

    /// Whether Pip, the guide companion, is in the room.
    var showCompanion: Bool {
        didSet { UserDefaults.standard.set(showCompanion, forKey: companionKey) }
    }

    /// Whether SPAI says an instrument's name aloud when one is held up.
    var announceInstruments: Bool {
        didSet { UserDefaults.standard.set(announceInstruments, forKey: announceKey) }
    }

    /// The in-room tour has its own flag. The window onboarding sets
    /// `hasCompletedOnboarding` before the immersive space ever opens, so
    /// sharing that flag meant the in-room tour never ran.
    var hasSeenSpatialTour: Bool {
        didSet { UserDefaults.standard.set(hasSeenSpatialTour, forKey: spatialTourKey) }
    }

    /// The panel the guide is pointing at. It gets a highlighted border, and
    /// is shown even if the user had it closed.
    var spotlightPanel: String?

    /// True while the in-room tour is running; other panels dim so the
    /// spotlit one is the only thing asking for attention.
    var isTourActive = false

    /// Bumped to ask the immersive space to (re)start the tour.
    private(set) var tourRequestID = 0
    func requestTour() { tourRequestID += 1 }

    // MARK: - Event log

    var eventLog: [LogEvent] = []

    private func log(_ message: String, kind: LogEvent.Kind) {
        let time = Date().formatted(date: .omitted, time: .standard)
        eventLog.insert(LogEvent(timestamp: time, message: message, kind: kind), at: 0)
    }

    func logStationEntry(_ name: String, step: SterileStep) {
        log("Entered \(name) station", kind: .info)
    }

    func logInstrument(_ instrument: IdentifiedInstrument) {
        guard instrument.certain else { return }
        log("Identified \(instrument.name) (\(instrument.confidencePercent)%)", kind: .info)
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
        let defaults = UserDefaults.standard
        self.hasCompletedOnboarding = defaults.bool(forKey: onboardingKey)
        self.layout = defaults.string(forKey: layoutKey).flatMap(PanelLayout.init(rawValue:)) ?? .focus
        self.hasSeenSpatialTour = defaults.bool(forKey: spatialTourKey)
        // These two default to on, so "never set" has to read as true.
        self.showCompanion = defaults.object(forKey: companionKey) as? Bool ?? true
        self.announceInstruments = defaults.object(forKey: announceKey) as? Bool ?? true
        Task { _ = try? await client.resetCompliance() }
        log("Session started", kind: .info)
    }
}
