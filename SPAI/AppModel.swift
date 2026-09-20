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

extension SterileStep {
    /// True when this step requires glove/hand PPE detection.
    var needsPPEDetection: Bool {
        StationScripts.script(for: self).contains { $0.condition == .glovesOn }
    }

    /// True when this step requires instrument or tray detection.
    var needsInstrumentDetection: Bool {
        StationScripts.script(for: self).contains {
            $0.condition == .instrumentsPresent || $0.condition == .trayLoaded
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
    private let wristMenusKey = "wristMenusEnabled"
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

    /// Entry point for starting the tour, so the role is captured before it can be changed.
    func beginTour() {
        roleBeforeTour = role
        tour.start(wristMenusEnabled: wristMenusEnabled)
    }

    func completeTour() { hasCompletedTour = true }

    /// Puts back whatever the tour borrowed. Wired to `AppTour.onEnd`, so it covers every way
    /// the tour can stop — skipped, finished, or torn down with the immersive space.
    private func endTour() {
        guard let previous = roleBeforeTour else { return }
        roleBeforeTour = nil
        guard role != previous else { return }
        role = previous
        announce("Role restored to \(previous.rawValue)", icon: "person.crop.circle")
    }

    /// The role step has made its point by the time it is acknowledged. Leaving the user
    /// read-only past that strands them on the next step, which asks them to tap Start Step.
    private func restoreWorkflowRoleForTour() {
        guard isReadOnly else { return }
        let restored = roleBeforeTour ?? .technician
        guard role != restored else { return }
        role = restored
    }

    /// Replays the tour from Settings.
    func restartTour() {
        hasCompletedTour = false
        roleBeforeTour = role
        tour.start(wristMenusEnabled: wristMenusEnabled)
    }

    /// Role the user held before the tour borrowed it.
    ///
    /// The tour's role step says "Pick a different role to see it change", and taking it at
    /// its word means choosing Supervisor or Observer — both read-only. `canRunWorkflow` then
    /// turns `startStep` and `completeStep` into silent no-ops and disables the guided panel,
    /// and the *next* tour step asks the user to tap Start Step. They tap, nothing happens,
    /// the tour cannot advance past it, and every workflow control stays inert. Nothing put
    /// the role back either, so dismissing the tour left the user stranded as an Observer
    /// wondering why the app had stopped responding.
    private var roleBeforeTour: TechRole?

    var role: TechRole = .technician {
        didSet {
            guard role != oldValue else { return }
            
            SPAILog.info(.ui, "action fired: changedRole → \(role.rawValue)")
            tour.note(.changedRole)
            SPAILog.debug( SPAILog.Category.ui,"Role changed to \(role.rawValue)")
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

    // MARK: - Panel drag offsets

    /// World-space position deltas the user accumulates by dragging each panel's handle.
    /// In-memory only — resets when the immersive space closes so every session starts from
    /// the default arc layout.
    var panelDragOffsets: [String: SIMD3<Float>] = [:]

    func dragOffset(for panelID: String) -> SIMD3<Float> {
        panelDragOffsets[panelID] ?? .zero
    }

    func setDragOffset(_ offset: SIMD3<Float>, for panelID: String) {
        panelDragOffsets[panelID] = offset
    }

    /// Called from ImmersiveView.onDisappear so the next session uses the clean arc layout.
    func resetAllDragOffsets() {
        panelDragOffsets.removeAll()
    }

    // MARK: - Panel handle visibility

    /// Whether each panel's drag handle is shown. Persisted — hiding a handle is a
    /// preference, not session state.
    private let handleVisibleKey = "panelHandleVisible"
    private(set) var panelHandleVisible: [String: Bool] = [:]

    func isHandleVisible(for panelID: String) -> Bool {
        panelHandleVisible[panelID] ?? true   // default: shown
    }

    func setHandleVisible(_ visible: Bool, for panelID: String) {
        panelHandleVisible[panelID] = visible
        if let data = try? JSONEncoder().encode(panelHandleVisible) {
            UserDefaults.standard.set(data, forKey: handleVisibleKey)
        }
    }

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

    /// Whether the wrist-anchored menus are available at all. Some users would rather not have
    /// anything riding on their arms while they work.
    var wristMenusEnabled: Bool {
        didSet { UserDefaults.standard.set(wristMenusEnabled, forKey: wristMenusKey) }
    }

    // MARK: - Window toggles

    enum WindowToggle { case open, close, ignore }

    /// Debounce window for the auxiliary-window toggles.
    ///
    /// A gaze-pinch can register twice, and each extra press used to mint another Settings
    /// window. The scene is a singleton now so duplicates are impossible, but without this a
    /// double press still reads as open-then-immediately-close, which looks like the button
    /// did nothing.
    private var lastWindowToggleAt: Date = .distantPast
    private let windowToggleDebounce: TimeInterval = 0.5

    /// Single decision point for "the user pressed the Settings button", shared by the wrist
    /// menu and the status bar so the two can't drift apart again.
    func requestSettingsToggle() -> WindowToggle {
        requestWindowToggle(
            isOpen: { $0.isSettingsWindowOpen },
            setOpen: { $0.isSettingsWindowOpen = $1 },
            name: "Settings",
            icon: "gearshape.fill"
        )
    }

    /// Same treatment for the upload window, which is opened from three different places.
    func requestUploadToggle() -> WindowToggle {
        requestWindowToggle(
            isOpen: { $0.isUploadWindowOpen },
            setOpen: { $0.isUploadWindowOpen = $1 },
            name: "Upload",
            icon: "photo.badge.plus"
        )
    }

    private func requestWindowToggle(
        isOpen: (AppModel) -> Bool,
        setOpen: (AppModel, Bool) -> Void,
        name: String,
        icon: String
    ) -> WindowToggle {
        let now = Date()
        guard now.timeIntervalSince(lastWindowToggleAt) > windowToggleDebounce else {
            return .ignore
        }
        lastWindowToggleAt = now

        if isOpen(self) {
            setOpen(self, false)
            announce("\(name) closed", icon: icon)
            return .close
        } else {
            setOpen(self, true)
            announce("\(name) opened", icon: icon)
            return .open
        }
    }

    // MARK: - Action feedback

    /// A short confirmation of what the last tap actually did.
    ///
    /// Testing found the buttons had feedback that they'd been *hit*, but nothing said what
    /// happened or where it happened — so a panel opening off to one side read as nothing at
    /// all. This is shown right where the user is already looking.
    struct ActionFeedback: Equatable {
        let message: String
        let icon: String
        let at: Date
    }

    private(set) var lastAction: ActionFeedback?

    func announce(_ message: String, icon: String) {
        lastAction = ActionFeedback(message: message, icon: icon, at: Date())
    }

    /// Human-readable names for the toggleable panels, used in confirmations.
    static func panelDisplayName(_ id: String) -> String {
        switch id {
        case "chat":      return "Chat"
        case "history":   return "History"
        case "detection": return "Detection"
        case "eventLog":  return "Event Log"
        case "workflow":  return "Workflow"
        case "upload":    return "Upload"
        default:          return id.capitalized
        }
    }
    
    func isVisible(_ panelID: String) -> Bool { panelVisibility[panelID] ?? true }
    func showAllPanels() { panelVisibility.removeAll() }

    /// Panel that most recently became visible, and when. `ImmersiveView` reads this to play
    /// the "fly in from the button you tapped" transition, so a panel that opens off to the
    /// side announces itself instead of silently appearing outside the user's field of view.
    var lastOpenedPanel: (id: String, at: Date)?

    func toggleVisibility(_ panelID: String) {
        let nowVisible = !isVisible(panelID)
        panelVisibility[panelID] = nowVisible
        SPAILog.info(.ui, "action fired: toggleVisibility(\(panelID)) → \(nowVisible ? "shown" : "hidden")")

        let name = Self.panelDisplayName(panelID)
        announce(
            nowVisible ? "\(name) opened" : "\(name) closed",
            icon: nowVisible ? "rectangle.on.rectangle" : "rectangle.slash"
        )

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
        SPAILog.debug(.video,"Video: \(state) at \(timestamp) kind \(kind)")
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
        // `script.count - 1` is -1 for an empty script, which would index out of bounds and
        // trap. Not reachable with the scripts as written, but this is on the contamination
        // path — a crash here takes the safety check down with it.
        guard let idx = script.clampedIndex(guidedStepIndex) else { return false }
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
        SPAILog.info(.ui, "action fired: startStep → \(step.title)")
//        tour.note(.startedStep)
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
        // Defaults on: `bool(forKey:)` returns false for a key that was never written, which
        // would silently ship the feature disabled to everyone who has not opened Settings.
        self.wristMenusEnabled = UserDefaults.standard.object(forKey: wristMenusKey) as? Bool ?? true

        // Restore which panels the user has already hidden their drag handle on.
        if let data = UserDefaults.standard.data(forKey: handleVisibleKey),
           let stored = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.panelHandleVisible = stored
        }

        // The tour drives real controls, so it can leave real state behind it. These two hand
        // that state back: one the moment a step's demonstration has landed, the other however
        // the tour ends.
        tour.onStepSatisfied = { [weak self] event in
            guard event == .changedRole else { return }
            self?.restoreWorkflowRoleForTour()
        }
        tour.onEnd = { [weak self] in self?.endTour() }

        Task { _ = try? await client.resetCompliance() }
        log("Session started", kind: .info)
    }
}
