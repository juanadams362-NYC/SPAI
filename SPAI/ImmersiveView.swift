//
//  ImmersiveView.swift
//  SPAI
//

import SwiftUI
import RealityKit
import RealityKitContent
import simd
import UIKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @Environment(ContinuityCameraService.self) private var continuityCamera

    @State private var stationManager = StationManager()
    @State private var handTracking = HandTrackingService()
    @State private var guide = GuideCompanion()
    @State private var headsetCamera = CameraFrameService()
    /// Parent of every room panel and of Pip. Moving this one entity moves
    /// the whole workspace, which is how it is fitted to the user.
    @State private var workspace = Entity()
    @AppStorage("useHeadsetCamera") private var useHeadsetCamera = true
    /// The "press Start Step" nudge is only worth saying once per session.
    @State private var hasNudgedToStart = false

    // MARK: - Layout

    /// Where a panel sits on the arc around the user.
    private struct Slot {
        let id: String
        /// Degrees left (-) or right (+) of straight ahead.
        let angle: Float
        /// Metres above the floor.
        let height: Float
        /// Metres from the user.
        let radius: Float
    }

    /// The workspace, in three rings of importance:
    ///
    /// - **Centre** — what you act on: the workflow and the current step.
    /// - **Just left** — what you glance at: detection.
    /// - **Outer edges** — reference panels, closed until asked for.
    ///
    /// In the Focus layout only the first two rings are open, so a new user
    /// meets three panels instead of ten.
    private static let slots: [Slot] = [
        Slot(id: PanelID.statusBar, angle: 0,   height: 1.72, radius: 1.35),
        Slot(id: PanelID.workflow,  angle: 0,   height: 0.88, radius: 1.10),
        Slot(id: PanelID.guided,    angle: 12,  height: 1.22, radius: 1.15),
        Slot(id: PanelID.report,    angle: 0,   height: 1.38, radius: 1.05),
        Slot(id: PanelID.detection, angle: -30, height: 1.42, radius: 1.20),

        Slot(id: PanelID.eventLog,  angle: 32,  height: 1.42, radius: 1.20),
        Slot(id: PanelID.chat,      angle: 54,  height: 1.40, radius: 1.25),
        Slot(id: PanelID.history,   angle: -54, height: 1.48, radius: 1.25),
        Slot(id: PanelID.upload,    angle: -54, height: 0.95, radius: 1.25)
    ]

    /// Panels the user opens and closes; everything else is driven by workflow state.
    private static let toggleablePanels = [
        PanelID.statusBar, PanelID.workflow, PanelID.detection,
        PanelID.eventLog, PanelID.chat, PanelID.history, PanelID.upload
    ]

    /// The panel heights above assume eyes about this far off the floor.
    /// The workspace is raised or lowered by the difference for each user.
    private static let designEyeHeight: Float = 1.6

    /// RealityView attachments are laid out at this many points per metre.
    private static let pointsPerMeter: Float = 1360

    var body: some View {
        realityContent
            .onAppear(perform: enterSpace)
            .onDisappear(perform: leaveSpace)
            .onChange(of: appModel.tourRequestID) { _, _ in
                guard appModel.showCompanion else { return }
                guide.startTour()
            }
            .onChange(of: appModel.recenterRequestID) { _, _ in
                fitWorkspaceToUser(animated: true)
            }
            .onChange(of: detectionService.mode) { _, mode in
                appModel.detectionModeLabel = mode.rawValue
            }
            .onChange(of: headsetCamera.statusMessage) { _, message in
                appModel.cameraNote = message
            }
            .onChange(of: appModel.isHalted) { _, halted in
                reactToHalt(halted)
            }
            .onChange(of: appModel.stepStarted) { _, _ in settleGuide() }
            .onChange(of: appModel.currentStepIndex) { _, _ in settleGuide() }
            .onChange(of: appModel.sessionComplete) { _, _ in settleGuide() }
            .onChange(of: detectionService.announcementRevision) { _, _ in
                announceInstrument()
            }
            .onChange(of: guide.isTourRunning) { _, running in
                guard !running else { return }
                // Tour finished or skipped: let Pip finish its hop, then go
                // and wait where the next action is.
                Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    settleGuide()
                }
            }
    }

    // MARK: - Scene

    private var realityContent: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            // Room panels, on the arc.
            var placed: [String: Entity] = [:]
            for slot in Self.slots {
                guard let panel = attachments.entity(for: slot.id) else { continue }
                panel.position = Self.arcPosition(angle: slot.angle, height: slot.height, radius: slot.radius)
                workspace.addChild(panel)
                placed[slot.id] = panel
            }
            content.add(workspace)

            // Alerts and narration come from the panel they're about.
            if let detection = placed[PanelID.detection] {
                detection.spatialAudio = SpatialAudioComponent()
                SoundManager.shared.contaminationAnchor = detection
            }
            if let guided = placed[PanelID.guided] {
                guided.spatialAudio = SpatialAudioComponent()
                SpeechManager.shared.guidedAnchor = guided
            }

            // Wrist menus. They always turn to face the user, whatever the
            // "panels look at you" setting says — a wrist menu seen edge-on
            // is unreadable.
            let stationPicker = attachments.entity(for: PanelID.stationPicker)
            let wristMenu = attachments.entity(for: PanelID.wristMenu)
            for menu in [stationPicker, wristMenu] {
                guard let menu else { continue }
                menu.components.set(BillboardComponent())
                content.add(menu)
            }
            handTracking.attach(stationPicker, to: .left,
                                panelSize: Self.meters(StationPickerPanel.compactSize))
            handTracking.attach(wristMenu, to: .right,
                                panelSize: Self.meters(WristMenuPanel.size))
            #if targetEnvironment(simulator)
            // No hand tracking in the simulator: park the menus in the room.
            handTracking.showAtFixedPositions(
                left: Self.arcPosition(angle: -30, height: 0.85, radius: 1.2),
                right: Self.arcPosition(angle: -70, height: 0.9, radius: 1.2)
            )
            #endif

            // Pip and its speech bubble.
            workspace.addChild(guide.root)
            let bubble = attachments.entity(for: PanelID.guideBubble)
            if let bubble {
                bubble.components.set(BillboardComponent())
                workspace.addChild(bubble)
            }
            guide.attach(panels: placed, bubble: bubble, appModel: appModel)

            applyState(attachments)

            // Give the room a moment to appear, put it where this user can
            // see it, and only then let Pip start talking.
            Task {
                await fitWorkspaceWhenTrackingIsReady()
                try? await Task.sleep(for: .seconds(0.8))
                beginGuide()
            }
        } update: { _, attachments in
            applyState(attachments)
        } attachments: {
            Attachment(id: PanelID.statusBar) { StatusBarPanel() }
            Attachment(id: PanelID.workflow)  { WorkflowProgressPanel() }
            Attachment(id: PanelID.guided)    { GuidedStepPanel() }
            Attachment(id: PanelID.report)    { SessionReportPanel() }
            Attachment(id: PanelID.detection) { DetectionPanel(service: detectionService) }

            Attachment(id: PanelID.eventLog)  { EventLogPanel() }
            Attachment(id: PanelID.chat)      { ChatPanel() }
            Attachment(id: PanelID.history)   { SessionHistoryPanel() }
            Attachment(id: PanelID.upload)    { DetectionUploadPanel(service: detectionService) }

            Attachment(id: PanelID.stationPicker) {
                // Left wrist: station picker.
                StationPickerPanel(manager: stationManager, compact: true)
            }
            Attachment(id: PanelID.wristMenu) {
                // Right wrist: quick actions.
                WristMenuPanel()
            }
            Attachment(id: PanelID.guideBubble) {
                GuideBubbleView(guide: guide)
            }
        }
    }

    /// Pushes current app state onto the entities. Runs once at setup and
    /// again whenever anything it reads changes.
    private func applyState(_ attachments: RealityViewAttachments) {
        for id in Self.toggleablePanels {
            attachments.entity(for: id)?.isEnabled = appModel.isShown(id)
        }

        attachments.entity(for: PanelID.report)?.isEnabled = appModel.sessionComplete
        attachments.entity(for: PanelID.guided)?.isEnabled =
            appModel.stepStarted && !appModel.sessionComplete && appModel.canRunWorkflow

        guide.root.isEnabled = appModel.showCompanion
        attachments.entity(for: PanelID.guideBubble)?.isEnabled =
            appModel.showCompanion && guide.message != nil

        for slot in Self.slots {
            guard let panel = attachments.entity(for: slot.id) else { continue }
            if appModel.panelsBillboard {
                panel.components.set(BillboardComponent())
            } else {
                panel.components.remove(BillboardComponent.self)
            }
        }
    }

    // MARK: - Lifecycle

    private func enterSpace() {
        appModel.immersiveSpaceState = .open

        stationManager.onEnter = { station in
            appModel.currentStepIndex = station.step.rawValue
            appModel.stepStarted = false
            appModel.logStationEntry(station.name, step: station.step)
        }

        // Live camera frames feed detection for as long as the workspace is
        // open. Previously this was only hooked up while the upload window
        // happened to be on screen, so closing that window silently stopped
        // live detection.
        continuityCamera.onFrameForDetection = { image in
            await detectionService.detect(
                image: image,
                step: SterileStep(rawValue: appModel.currentStepIndex),
                preferOnDevice: false
            )
        }

        appModel.detectionModeLabel = detectionService.mode.rawValue
        // Pick up the school's latest wording and send any runs that were
        // finished while offline.
        Task {
            await ProtocolStore.shared.refresh()
            await appModel.flushUploads()
        }

        #if !targetEnvironment(simulator)
        Task { await stationManager.startImageTracking() }
        Task { await handTracking.start() }
        startHeadsetCamera()
        #endif
    }

    /// Feeds detection from the headset's own camera, so a student needs
    /// nothing but the headset. Requires Apple's main-camera entitlement;
    /// without it the camera reports why and the other sources still work.
    private func startHeadsetCamera() {
        guard useHeadsetCamera else {
            appModel.cameraNote = nil
            return
        }
        headsetCamera.onFrameForDetection = { buffer in
            guard let image = UIImage.from(readOnlyBuffer: buffer) else { return }
            Task {
                await detectionService.detect(
                    image: image,
                    step: SterileStep(rawValue: appModel.currentStepIndex),
                    preferOnDevice: false
                )
            }
        }
        Task { await headsetCamera.start() }
    }

    // MARK: - Fitting the workspace to the user

    /// Hand and head tracking take a moment to start. Wait for a head pose
    /// (briefly), then place the workspace. In the simulator there is no
    /// pose and the workspace stays at its designed position.
    private func fitWorkspaceWhenTrackingIsReady() async {
        for _ in 0..<12 {
            try? await Task.sleep(for: .seconds(0.25))
            if handTracking.headPose() != nil {
                fitWorkspaceToUser(animated: false)
                return
            }
        }
    }

    /// Turns the workspace to face the way the user is looking and raises
    /// or lowers it to their eye height. Panels used to sit at fixed heights
    /// in a fixed direction, which put them out of view for anyone seated,
    /// shorter or taller than the design assumed, or facing another way.
    private func fitWorkspaceToUser(animated: Bool) {
        guard let head = handTracking.headPose() else { return }
        // Rotating by this angle about Y turns the workspace's "ahead" (-Z)
        // to the direction the user faces.
        let yaw = atan2(-head.forward.x, -head.forward.z)
        let lift = min(max(head.position.y - Self.designEyeHeight, -0.65), 0.35)
        let target = Transform(
            rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]),
            translation: [head.position.x, lift, head.position.z]
        )
        if animated {
            workspace.move(to: target, relativeTo: workspace.parent, duration: 0.6, timingFunction: .easeInOut)
        } else {
            workspace.transform = target
        }
    }

    private func leaveSpace() {
        appModel.immersiveSpaceState = .closed
        appModel.spotlightPanel = nil
        appModel.isTourActive = false
        guide.detach()
        // Leaving mid-run still records the run, as incomplete, and the
        // headset is cleared for the next student.
        appModel.signOut()
        #if !targetEnvironment(simulator)
        handTracking.stop()
        headsetCamera.stop()
        #endif
        SoundManager.shared.contaminationAnchor = nil
        SpeechManager.shared.guidedAnchor = nil
    }

    // MARK: - Guide behaviour

    /// First thing Pip does once the room is up: run the tour for a new
    /// user, otherwise go and wait where the next action is.
    private func beginGuide() {
        guard appModel.showCompanion else { return }
        if appModel.hasSeenSpatialTour {
            settleGuide()
        } else {
            // The tour ends by pointing at Start Step, so the nudge would
            // only repeat it.
            hasNudgedToStart = true
            guide.startTour()
        }
    }

    /// Sends Pip to wherever the user's attention belongs for the current
    /// workflow state.
    private func settleGuide() {
        guard appModel.showCompanion, !guide.isTourRunning, !appModel.isHalted else { return }

        if appModel.sessionComplete {
            guide.setMood(.happy)
            guide.perch(on: PanelID.report)
            return
        }

        guide.setMood(.calm)

        if appModel.stepStarted && appModel.canRunWorkflow {
            // The instruction is the thing to read now; sit on it.
            guide.perch(on: PanelID.guided)
            return
        }

        guide.perch(on: PanelID.workflow)
        if appModel.canRunWorkflow && !hasNudgedToStart {
            hasNudgedToStart = true
            guide.say(GuideMessage(
                title: "Ready when you are",
                text: "Press Start Step and I'll walk you through \(appModel.currentStep.title).",
                kind: .hint,
                icon: "play.circle.fill"
            ), duration: 7)
        }
    }

    /// Contamination: Pip jumps to the panel that raised it, then to the
    /// panel with the button that clears it.
    private func reactToHalt(_ halted: Bool) {
        guard appModel.showCompanion else { return }

        guard halted else {
            guide.setMood(.calm)
            guide.clearMessage()
            guide.spotlight(nil)
            settleGuide()
            return
        }

        guide.setMood(.alert)
        guide.perch(on: PanelID.detection)
        guide.spotlight(PanelID.detection, for: 3.5)
        guide.say(GuideMessage(
            title: "Bare hand spotted",
            text: appModel.canRunWorkflow
                ? "Put your gloves on, then press Acknowledge & Resume."
                : "The workflow is paused until the technician acknowledges it.",
            kind: .alert,
            icon: "exclamationmark.triangle.fill"
        ), duration: nil)

        guard appModel.canRunWorkflow else { return }
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            // Still halted? Show them where the button is.
            guard appModel.isHalted, !guide.isTourRunning else { return }
            guide.perch(on: PanelID.workflow)
            guide.spotlight(PanelID.workflow, for: 8)
        }
    }

    /// An instrument has been held up steadily enough to name.
    private func announceInstrument() {
        guard let instrument = detectionService.announcedInstrument else { return }
        appModel.logInstrument(instrument)

        if appModel.showCompanion {
            // At the inspection bench, also say what to check on it.
            let atInspection = appModel.currentStep == .inspection
            guide.say(GuideMessage(
                title: instrument.certain ? instrument.name : "Not sure which instrument",
                text: instrument.info?.summary ?? instrument.spoken,
                kind: instrument.certain ? .instrument(confidencePercent: instrument.confidencePercent) : .hint,
                icon: instrument.info?.icon ?? "questionmark.circle",
                points: atInspection ? (instrument.info?.inspect ?? []) : []
            ), duration: atInspection ? 12 : 8)
        }

        if appModel.announceInstruments {
            // Doesn't interrupt a step instruction or a safety alert.
            SpeechManager.shared.speakIfIdle(instrument.spoken, force: true, anchor: guide.root)
        }
    }

    // MARK: - Helpers

    private static func arcPosition(angle degrees: Float, height: Float, radius: Float) -> SIMD3<Float> {
        let a = degrees * .pi / 180
        return [radius * sin(a), height, -radius * cos(a)]
    }

    private static func meters(_ size: CGSize) -> SIMD2<Float> {
        SIMD2<Float>(Float(size.width), Float(size.height)) / pointsPerMeter
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
        .environment(DetectionService())
        .environment(ContinuityCameraService())
}
