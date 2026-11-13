//
//  AppModel.swift
//  SPAI
//

import SwiftUI
import UIKit

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

    /// Bumped to ask the immersive space to bring every panel back in
    /// front of the user, at their height.
    private(set) var recenterRequestID = 0
    func requestRecenter() { recenterRequestID += 1 }

    /// Why the headset's own camera isn't feeding detection, if it isn't.
    var cameraNote: String?

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
        if !instrumentsSeen.contains(instrument.name) { instrumentsSeen.append(instrument.name) }
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

    // MARK: - Who is working

    /// The roster entry signed in on this headset, or nil for a guest.
    var learner: Learner?
    /// Name typed by someone who isn't on the roster.
    var guestName: String = ""
    var runMode: RunMode = .assessed

    var learnerDisplayName: String {
        if let learner { return learner.name }
        let typed = guestName.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? "Guest" : typed
    }

    // MARK: - The run being recorded

    /// What happened this run, in a form the server can score. Kept
    /// alongside `eventLog` (which is for display) because scoring needs to
    /// know the kind of each event and which station it belongs to.
    private(set) var runEvents: [RunEvent] = []
    private(set) var instrumentsSeen: [String] = []
    private var runID = UUID().uuidString
    private var runFinished = false
    /// Where detection ran, for the record. Set by the immersive view.
    var detectionModeLabel = ""

    /// The result of the run that just ended, scored on the headset so it
    /// shows immediately, online or not.
    private(set) var lastResult: CompetencyResult?

    enum UploadState: Equatable {
        case none
        case sending
        case sent
        /// Couldn't reach the server; saved on the headset to send later.
        case waiting
        /// Practice runs and guest runs stay on the headset.
        case notRecorded
    }
    private(set) var uploadState: UploadState = .none

    private let pendingKey = "pendingRunUploads"
    /// Finished runs the server hasn't confirmed yet. Survives the app
    /// closing, so a run finished in a dead spot still reaches the instructor.
    private(set) var pendingUploads: [RunRecord] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pendingUploads) {
                UserDefaults.standard.set(data, forKey: pendingKey)
            }
        }
    }

    private func record(_ kind: String, _ message: String, station: SterileStep? = nil) {
        guard !runFinished else { return }
        runEvents.append(RunEvent(
            at: RunClock.stamp(),
            kind: kind,
            station: (station ?? currentStep).backendName,
            message: message
        ))
    }

    /// Called when the count sheet doesn't match as a tray is closed.
    func recordCountMismatch(_ summary: String) {
        log("Count sheet: \(summary)", kind: .warning)
        record("count_mismatch", "Count sheet did not match: \(summary)")
    }

    private var stationsCompleted: Int {
        Set(runEvents.filter { $0.kind == "station_complete" }.compactMap(\.station)).count
    }

    /// Starts a fresh run with a fresh server-side workflow.
    func beginRun() {
        runID = UUID().uuidString
        BackendClient.sessionID = runID
        runEvents = []
        instrumentsSeen = []
        runFinished = false
        lastResult = nil
        uploadState = .none
    }

    /// Ends a run that was started but not finished, so it is recorded as
    /// incomplete rather than lost. Does nothing if no station was started.
    func endRunEarly() {
        guard !runFinished, runEvents.contains(where: { $0.kind == "station_start" }) else { return }
        finishRun(completed: false)
    }

    private func finishRun(completed: Bool) {
        guard !runFinished else { return }
        runFinished = true

        let done = stationsCompleted
        lastResult = Competency.score(
            events: runEvents,
            completed: completed,
            stationsCompleted: done,
            rubric: ProtocolStore.shared.rubric
        )

        // Practice is a rehearsal and stays on the headset, as promised on
        // the sign-in screen.
        guard runMode == .assessed else {
            uploadState = .notRecorded
            return
        }

        pendingUploads.append(RunRecord(
            id: runID,
            learnerID: learner?.id,
            learnerName: learnerDisplayName,
            role: role.rawValue,
            mode: runMode.rawValue,
            headset: UIDevice.current.name,
            startedAt: RunClock.stamp(sessionStart),
            endedAt: RunClock.stamp(),
            durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
            completed: completed,
            stationsCompleted: done,
            events: runEvents,
            instrumentsSeen: instrumentsSeen,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            detectionMode: detectionModeLabel
        ))
        Task { await flushUploads() }
    }

    /// Sends every run the server hasn't confirmed. Safe to call any time:
    /// the server replaces a run it already has, so a retry can't duplicate.
    func flushUploads() async {
        guard !pendingUploads.isEmpty, uploadState != .sending else { return }
        uploadState = .sending
        for run in pendingUploads {
            do {
                _ = try await client.uploadRun(run)
                pendingUploads.removeAll { $0.id == run.id }
            } catch {
                uploadState = .waiting
                return
            }
        }
        uploadState = .sent
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

    /// Reads the current step again, on request — whether or not spoken
    /// guidance is switched on, because the user just asked for it.
    func repeatGuidedStep() {
        let script = StationScripts.script(for: currentStep)
        guard stepStarted, !script.isEmpty else { return }
        SpeechManager.shared.speak(script[min(max(guidedStepIndex, 0), script.count - 1)].instruction, force: true)
    }

    /// Records that a camera-checked step was confirmed by hand instead.
    func recordManualOverride(_ reason: String) {
        log("Confirmed by hand: \(reason)", kind: .info)
        record("manual_override", "Step confirmed by hand: \(reason)")
    }

    func advanceGuidedStep() {
        let script = StationScripts.script(for: currentStep)
        guard guidedStepIndex < script.count - 1 else { return }
        guidedStepIndex += 1
        speakCurrentGuidedStep()
    }

    /// Tells the server about a workflow event, without waiting on it.
    ///
    /// The headset is the source of truth for where the student is. The
    /// server keeps a matching record, but a slow, restarted or unreachable
    /// server must never stop someone starting or finishing a step — that
    /// used to freeze the workflow for up to fifteen seconds, or for good.
    /// If the two disagree, it is noted in the log and work carries on.
    private func notifyServer(_ event: String, step: SterileStep? = nil) {
        Task {
            guard let result = try? await client.sendComplianceEvent(event, step: step?.backendName),
                  !result.accepted else { return }
            log("Server record out of step: \(result.message)", kind: .info)
        }
    }

    func startStep() {
        guard canRunWorkflow, !stepStarted, !sessionComplete else { return }
        let step = currentStep
        stepStarted = true
        guidedStepIndex = 0
        log("Started \(step.title)", kind: .info)
        record("station_start", "Started \(step.title)")
        speakCurrentGuidedStep()
        notifyServer("start_step", step: step)
    }

    func completeStep() {
        guard canRunWorkflow, stepStarted, !isHalted else { return }
        let completed = currentStep
        record("station_complete", "Completed \(completed.title)", station: completed)
        if currentStepIndex < SterileStep.allCases.count - 1 {
            currentStepIndex += 1
            log("Completed \(completed.title)", kind: .success)
        } else {
            log("Completed \(completed.title) — workflow complete", kind: .success)
            sessionComplete = true
            finishRun(completed: true)
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
        notifyServer("complete_step", step: completed)
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
        record("send_back", "Failed \(failed.title) — tray sent back to Decontamination", station: failed)
        Task { _ = try? await client.resetCompliance() }
    }

    func raiseContamination() {
        isHalted = true
        log("Contamination detected — workflow halted", kind: .warning)
        record("contamination", "Contamination detected — workflow halted")
        contaminationCount += 1
        notifyServer("contamination")
    }

    func acknowledgeContamination() {
        guard canRunWorkflow else { return }
        isHalted = false
        log("Contamination acknowledged — workflow resumed", kind: .info)
        record("acknowledge", "Contamination acknowledged — workflow resumed")
        notifyServer("acknowledge")
    }

    func redoStep() {
        guard canRunWorkflow else { return }
        let step = currentStep
        stepStarted = false
        guidedStepIndex = 0
        SpeechManager.shared.stop()
        log("Redo \(step.title)", kind: .info)
        record("redo", "Redo \(step.title)")
    }

    func resetWorkflow() {
        // Abandoning a run that had started still counts as a run: the
        // instructor should see that it was begun and not finished.
        endRunEarly()
        beginRun()
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
        BackendClient.sessionID = runID
        if let data = defaults.data(forKey: pendingKey),
           let saved = try? JSONDecoder().decode([RunRecord].self, from: data) {
            self.pendingUploads = saved
        }
        Task { _ = try? await client.resetCompliance() }
        log("Session started", kind: .info)
    }
}
