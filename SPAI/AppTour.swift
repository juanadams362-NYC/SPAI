//
//  AppTour.swift
//  SPAI
//
//  Progressive, in-app guided tour.
//

import Foundation

/// Something the user did that a tour step can be waiting on.
///
/// Steps advance when the user performs the real action, not when they tap "Next" on a slide.
/// That is the whole point of the rewrite: the previous onboarding was a stack of pages shown
/// before the app opened, so the tester still arrived at the workspace not knowing what any of
/// it did and spent several minutes working it out.
enum TourEvent: Equatable {
    case changedRole
    case startedStep
    case openedChat
    case openedHistory
    case openedSettings
    case openedUpload
}

/// Which panel a coachmark should sit beside. Matches the attachment IDs in `ImmersiveView`.
enum TourAnchor: String {
    case center
    case statusBar
    case detection
    case eventLog
    case workflow
    case guided
    case upload
    case wristMenu
}

struct TourStep: Identifiable {
    let id: Int
    let title: String
    let message: String
    let anchor: TourAnchor

    /// The action that completes this step. `nil` means the step is purely informational and
    /// advances on "Next".
    let advanceOn: TourEvent?

    /// Prompt shown in place of the "Next" button while waiting for `advanceOn`.
    let callToAction: String?

    init(
        id: Int,
        title: String,
        message: String,
        anchor: TourAnchor,
        advanceOn: TourEvent? = nil,
        callToAction: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.anchor = anchor
        self.advanceOn = advanceOn
        self.callToAction = callToAction
    }
}

@MainActor
@Observable
final class AppTour {
    enum Phase: Equatable {
        /// Not showing anything.
        case idle
        /// Asking whether the user wants the tour at all. Always skippable.
        case offered
        /// Walking through `steps`.
        case running
        /// Final card.
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var stepIndex: Int = 0

    /// Set when the user completes the action a step was waiting for, so the card can
    /// acknowledge it for a beat before moving on.
    private(set) var justSatisfied: Bool = false

    var currentStep: TourStep? {
        guard phase == .running, steps.indices.contains(stepIndex) else { return nil }
        return steps[stepIndex]
    }

    /// Panel the coachmark should currently sit beside.
    var anchor: TourAnchor {
        switch phase {
        case .idle:                 return .center
        case .offered, .finished:   return .center
        case .running:              return currentStep?.anchor ?? .center
        }
    }

    var isVisible: Bool { phase != .idle }

    var progress: (current: Int, total: Int) {
        (min(stepIndex + 1, steps.count), steps.count)
    }

    // MARK: - Control

    func offer(wristMenusEnabled: Bool = true) {
        guard phase == .idle else { return }
        steps = Self.script(wristMenusEnabled: wristMenusEnabled)
        phase = .offered
    }

    func start(wristMenusEnabled: Bool = true) {
        steps = Self.script(wristMenusEnabled: wristMenusEnabled)
        stepIndex = 0
        justSatisfied = false
        phase = .running
    }

    func next() {
        justSatisfied = false
        guard phase == .running else { return }
        if stepIndex < steps.count - 1 {
            stepIndex += 1
        } else {
            phase = .finished
        }
    }

    func back() {
        justSatisfied = false
        guard phase == .running, stepIndex > 0 else { return }
        stepIndex -= 1
    }

    /// Ends the tour without marking it complete, so it can be offered again.
    func skip() {
        phase = .idle
        stepIndex = 0
        justSatisfied = false
    }

    /// Ends the tour for good.
    func finish() {
        phase = .idle
        stepIndex = 0
        justSatisfied = false
    }

    /// Tears the tour down when the immersive space closes.
    func stop() {
        phase = .idle
        stepIndex = 0
        justSatisfied = false
    }

    /// Called from the app's real controls. If the current step was waiting on this action,
    /// the tour moves on by itself — the user learns by doing rather than by reading.
    func note(_ event: TourEvent) {
        guard phase == .running, let step = currentStep, step.advanceOn == event else { return }
        justSatisfied = true
        Task { @MainActor in
            // Let the user see the result of what they just did before the card moves on.
            try? await Task.sleep(for: .milliseconds(900))
            guard self.justSatisfied else { return }
            self.next()
        }
    }

    // MARK: - Script

    /// Ordered so the user reaches a real result early — a started step with live guidance —
    /// before the tour branches out into the supporting panels.
    ///
    /// Rebuilt whenever the tour starts, because the script depends on whether the wrist menus
    /// are switched on: with them off, "tap Chat on your wrist" is an instruction the user
    /// cannot follow, and the step explaining the wrist menu has nothing to explain.
    private(set) var steps: [TourStep] = AppTour.script(wristMenusEnabled: true)

    static func script(wristMenusEnabled: Bool) -> [TourStep] {
        var steps = baseSteps(wristMenusEnabled: wristMenusEnabled)
        // IDs double as the ordering contract, so renumber after any filtering.
        steps = steps.enumerated().map { index, step in
            TourStep(
                id: index,
                title: step.title,
                message: step.message,
                anchor: step.anchor,
                advanceOn: step.advanceOn,
                callToAction: step.callToAction
            )
        }
        return steps
    }

    private static func baseSteps(wristMenusEnabled: Bool) -> [TourStep] {
        let wristSteps: [TourStep] = wristMenusEnabled ? [
            TourStep(
                id: 0,
                title: "Your wrist menus",
                message: "Turn your right wrist toward you, like checking the time, and a menu appears beside it: Reset, History, Chat, Settings. Hold your left forearm level, as if a book were lying on it, for the station list. Both fade the moment you lower your arm.",
                anchor: .wristMenu
            )
        ] : []

        let chatCTA = wristMenusEnabled ? "Tap Chat on your wrist" : "Tap \"Ask SPAI\" in the status bar"
        let historyCTA = wristMenusEnabled ? "Tap History on your wrist" : "Tap History in the quick actions"
        let settingsCTA = wristMenusEnabled ? "Tap Settings on your wrist" : "Tap Settings in the status bar"
        let chatAnchor: TourAnchor = wristMenusEnabled ? .wristMenu : .statusBar
        let historyAnchor: TourAnchor = wristMenusEnabled ? .wristMenu : .eventLog
        let settingsAnchor: TourAnchor = wristMenusEnabled ? .wristMenu : .statusBar

        return coreSteps
            + wristSteps
            + [
                TourStep(
                    id: 0,
                    title: "Ask SPAI anything",
                    message: "Chat opens an assistant that knows your current step. Ask it out loud or by typing — it's the fastest way to get unstuck.",
                    anchor: chatAnchor,
                    advanceOn: .openedChat,
                    callToAction: chatCTA
                ),
                TourStep(
                    id: 0,
                    title: "Past sessions",
                    message: "History holds every completed session, and lets you compare two side by side to see what changed.",
                    anchor: historyAnchor,
                    advanceOn: .openedHistory,
                    callToAction: historyCTA
                ),
                TourStep(
                    id: 0,
                    title: "Feed it images",
                    message: "Upload a photo or video, or connect your iPhone as a camera, and SPAI runs detection against it. Useful for testing without a full tray in front of you.",
                    anchor: .upload
                ),
                TourStep(
                    id: 0,
                    title: "Make it yours",
                    message: "Settings holds the backend URL, the confidence threshold, panel opacity, whether panels turn to face you, and whether the wrist menus are on at all.",
                    anchor: settingsAnchor,
                    advanceOn: .openedSettings,
                    callToAction: settingsCTA
                )
            ]
    }

    /// The part of the script that is the same however the app is configured.
    private static let coreSteps: [TourStep] = [
        TourStep(
            id: 0,
            title: "Your status bar",
            message: "Session time, your role, and whether detection is running on-device or in the cloud. It sits above your eye line so it stays out of your way.",
            anchor: .statusBar
        ),
        TourStep(
            id: 1,
            title: "You have a role",
            message: "Technicians and Trainees can run a workflow. Supervisors and Observers can watch and review, but can't start steps. Pick a different role to see it change.",
            anchor: .statusBar,
            advanceOn: .changedRole,
            callToAction: "Tap any role above"
        ),
        TourStep(
            id: 2,
            title: "The five steps",
            message: "Decontamination, Inspection, Tray Assembly, Packaging, Seal Validation. This panel always shows which one you're on — you shouldn't have to ask.",
            anchor: .workflow
        ),
        TourStep(
            id: 3,
            title: "Start working",
            message: "Tap Start Step. SPAI reads each instruction aloud and moves you along as you complete them.",
            anchor: .workflow,
            advanceOn: .startedStep,
            callToAction: "Tap Start Step"
        ),
        TourStep(
            id: 4,
            title: "Guided instructions",
            message: "Your current instruction lives here, and it advances on its own as you work. This is the panel to look at when you're not sure what to do next.",
            anchor: .guided
        ),
        TourStep(
            id: 5,
            title: "What SPAI is watching",
            message: "Gloves, bare hands, and contamination risk. It needs to see your hands — sleeves or a hoodie covering them will read as no gloves. It does not need bare skin, just an unobstructed view.",
            anchor: .detection
        ),
        TourStep(
            id: 6,
            title: "Confidence",
            message: "The percentage is how sure SPAI is about what it sees. Below the threshold in Settings, it stays quiet rather than guessing. Raise the threshold for fewer false alarms, lower it to catch more.",
            anchor: .detection
        ),
        TourStep(
            id: 7,
            title: "If something goes wrong",
            message: "A bare hand at the wrong moment halts the workflow and sounds an alert from the direction of this panel. You'll hear it. Acknowledge it to carry on.",
            anchor: .detection
        ),
        TourStep(
            id: 8,
            title: "Everything is logged",
            message: "Every step, alert, and acknowledgement lands here with a timestamp, and gets saved as a session report you can export.",
            anchor: .eventLog
        )
    ]
}
