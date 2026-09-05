//
//  ImmersiveView.swift
//  SPAI
//

import SwiftUI
import RealityKit
import RealityKitContent
import simd

/// Where a panel sits on the arc around the user.
///
/// `heightAboveEye` is relative to the wearer's measured eye line rather than absolute, so
/// "status bar above eye level" stays true whether the user is tall, short, or seated.
private struct PanelSlot {
    let angle: Float
    let heightAboveEye: Float
    let radius: Float
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(DetectionService.self) private var detectionService
    @State private var stationManager = StationManager()

    @State private var cameraService = CameraFrameService()
    @State private var handTracking = HandTrackingService()
    @State private var headAnchor = HeadAnchorService()

    /// Not `@State`: this is bookkeeping for the entrance animation, and mutating it must not
    /// invalidate the view — doing that from inside a RealityView update closure would loop.
    @State private var entranceLog = PanelEntranceLog()

    private let arcRadius: Float = 1.25

    /// The full arc. Angles are degrees clockwise from straight ahead; heights are relative to
    /// the wearer's eye line; radius is metres out.
    private static let layout: [String: PanelSlot] = [
        // Above the eye line and pushed further back — it is the widest panel in the scene,
        // so at close range it dominates the view instead of reading as a header.
        "statusBar":     PanelSlot(angle:   0, heightAboveEye:  0.40, radius: 1.55),

        "detection":     PanelSlot(angle: -34, heightAboveEye: -0.05, radius: 1.25),
        "eventLog":      PanelSlot(angle:  34, heightAboveEye: -0.05, radius: 1.25),
        "guided":        PanelSlot(angle:  16, heightAboveEye: -0.35, radius: 1.15),
        "workflow":      PanelSlot(angle:   0, heightAboveEye: -0.65, radius: 1.15),
        "actions":       PanelSlot(angle:  54, heightAboveEye: -0.25, radius: 1.35),
        "report":        PanelSlot(angle:   0, heightAboveEye: -0.10, radius: 1.05),

        // Chat and history are deliberate mirror images. History used to sit lower and wider
        // out (-52°, 1.55 m) than chat (48°, 1.7 m), which is a large part of why "tap History"
        // read as doing nothing: the panel opened behind the user's shoulder, off to the side
        // they were not looking at, with no motion to draw the eye.
        "chat":          PanelSlot(angle:  46, heightAboveEye:  0.20, radius: 1.30),
        "history":       PanelSlot(angle: -46, heightAboveEye:  0.20, radius: 1.30),

        "upload":        PanelSlot(angle: -54, heightAboveEye: -0.50, radius: 1.35),
        "wristMenu":     PanelSlot(angle: -70, heightAboveEye: -0.60, radius: 1.20),
        "stationPicker": PanelSlot(angle: -30, heightAboveEye: -0.65, radius: 1.20)
    ]

    var body: some View {
        realityContent
        .onAppear {
            appModel.immersiveSpaceState = .open

            stationManager.onEnter = { station in
                appModel.currentStepIndex = station.step.rawValue
                appModel.stepStarted = false
                appModel.logStationEntry(station.name, step: station.step)
            }
            #if !targetEnvironment(simulator)
            // The wrist gestures are about the wrist *relative to the face*, so hand tracking
            // needs a live head position to test against.
            handTracking.headPositionProvider = { [headAnchor] in headAnchor.currentHeadPosition() }
            Task { await stationManager.startImageTracking() }
            Task { await handTracking.start() }
            #endif
        }
        .task {
            // Measure the wearer's eye line before the arc settles, so panel heights are
            // relative to them rather than to an assumed 1.5 m.
            await headAnchor.calibrate()
        }
        .task {
            // The guided tour is offered once the space is up and the panels exist to point
            // at. It is opt-in and skippable — see AppTour.
            guard !appModel.hasCompletedTour else { return }
            try? await Task.sleep(for: .seconds(1.2))
            appModel.tour.offer(wristMenusEnabled: appModel.wristMenusEnabled)
        }

        #if !targetEnvironment(simulator)
        .task {
            // Legacy ARKit camera path (requires special entitlements). Disabled by default
            // now that Continuity Camera is integrated. Leave in place for reference.
            // If you do enable this, ensure you are not also running ContinuityCameraService.
            /*
            cameraService.onFrameForDetection = { readOnlyBuffer in
                guard let image = UIImage.from(readOnlyBuffer: readOnlyBuffer) else { return }
                Task { await detectionService.detect(image: image, step: SterileStep(rawValue: appModel.currentStepIndex)) }
            }
            await cameraService.start()
            */
        }
        #endif
        // Entering the workflow dismisses the "home" window, which takes RootSceneView — and
        // its scene-phase observer — with it. Without this, the main path into the app is
        // exactly the path where nothing is left to tear the immersive space down, which is
        // how immersive content ended up outliving the app during testing.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            Task { @MainActor in
                await dismissImmersiveSpace()
                appModel.immersiveSpaceState = .closed
            }
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            #if !targetEnvironment(simulator)
            cameraService.stop()
            #endif
            headAnchor.stop()
            appModel.tour.stop()
            SoundManager.shared.contaminationAnchor = nil
            SpeechManager.shared.guidedAnchor = nil
        }
    }
    
    private var realityContent: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            for id in Self.layout.keys {
                place(id, content, attachments)
            }

            // The tour card has no fixed slot — it moves to whichever panel is being
            // explained — so it is not in `layout` and has to be added to the scene here.
            if let tourCard = attachments.entity(for: "tour") {
                tourCard.isEnabled = false
                content.add(tourCard)
            }

            if let detectionEntity = attachments.entity(for: "detection") {
                detectionEntity.spatialAudio = SpatialAudioComponent()
                SoundManager.shared.contaminationAnchor = detectionEntity
            }
            if let guidedEntity = attachments.entity(for: "guided") {
                guidedEntity.spatialAudio = SpatialAudioComponent()
                SpeechManager.shared.guidedAnchor = guidedEntity
            }
        } update: { _, attachments in
            setEnabled("statusBar", attachments)
            setEnabled("detection", attachments)
            setEnabled("eventLog",  attachments)
            setEnabled("workflow",  attachments)
            setEnabled("chat", attachments)
            setEnabled("history", attachments)
            setEnabled("upload", attachments)
            setEnabled("actions", attachments)

            // The wrist panels stay enabled and fade themselves out when tracking drops.
            // Disabling the entity the moment the pose went nil would cut the fade off
            // mid-animation and read as the same abrupt pop the freeze did.
            attachments.entity(for: "stationPicker")?.isEnabled = true
            attachments.entity(for: "wristMenu")?.isEnabled = true

            updateWristAnchor(
                "wristMenu", attachments,
                pose: handTracking.rightWristPose,
                // Out to the side of the forearm, not hovering over it. 0.06 m put the panel
                // physically in the way of the user's hands while they worked. With the 2×2
                // tile being ~8 cm across, a 0.16 m centre leaves its inner edge ~12 cm clear
                // of the arm and its outer edge ~20 cm out.
                offset: SIMD3<Float>(x: 0.16, y: 0.03, z: -0.03),
                fallback: arcPosition(for: "wristMenu")
            )
            updateWristAnchor(
                "stationPicker", attachments,
                pose: handTracking.leftWristPose,
                // Above the forearm — the ~13 cm the test plan called for. At y = 0.025 the
                // panel visually fused into the arm.
                offset: SIMD3<Float>(x: -0.04, y: 0.13, z: -0.03),
                fallback: arcPosition(for: "stationPicker")
            )

            // Panels are positioned once in `make`, but the eye-height sample lands a moment
            // later — so without this the calibration would compute a correct arc that
            // nothing ever moved to. Reposition once, when the measured height actually
            // changes, rather than every frame (which would fight the entrance animation).
            if entranceLog.appliedEyeHeight != headAnchor.eyeHeight {
                entranceLog.appliedEyeHeight = headAnchor.eyeHeight
                for id in Self.layout.keys where id != "wristMenu" && id != "stationPicker" {
                    attachments.entity(for: id)?.position = arcPosition(for: id)
                }
            }

            attachments.entity(for: "report")?.isEnabled = appModel.sessionComplete
            attachments.entity(for: "guided")?.isEnabled = appModel.stepStarted && !appModel.sessionComplete && appModel.canRunWorkflow

            for id in Self.layout.keys {
                updateBillboard(id, attachments)
            }

            // Fly a freshly-opened panel in from the wrist menu so the user can see where it
            // went — several panels open outside the field of view they are looking at.
            if let opened = appModel.lastOpenedPanel,
               entranceLog.handledAt != opened.at,
               appModel.isVisible(opened.id) {
                entranceLog.handledAt = opened.at
                animateEntrance(opened.id, attachments)
            }

            updateTourCard(attachments)
        } attachments: {
            Attachment(id: "statusBar") { StatusBarPanel() }
            Attachment(id: "detection") { DetectionPanel(service: detectionService) }
            Attachment(id: "eventLog")  { EventLogPanel() }
            Attachment(id: "workflow")  { WorkflowProgressPanel() }
            // Removed: camera panel (functionality merged into upload window)
            // Attachment(id: "camera")    { ContinuityCameraPanel() }
            #if true
            Attachment(id: "upload")   { DetectionUploadPanel(service: detectionService) }
            #endif
            Attachment(id: "chat") { ChatPanel() }
            Attachment(id: "actions") {
                ActionPanel(actions: [
                    QuickAction(label: "Show All", icon: "rectangle.3.group.fill", tint: SPAIColor.secondary) {
                        appModel.showAllPanels()
                    },
                    QuickAction(label: "Workflow", icon: "checklist", tint: SPAIColor.primary) {
                        appModel.toggleVisibility("workflow")
                    },
                    QuickAction(label: "Detection", icon: "viewfinder", tint: SPAIColor.accent) {
                        appModel.toggleVisibility("detection")
                    },
                    QuickAction(label: "Event Log", icon: "waveform.path.ecg", tint: SPAIColor.primary) {
                        appModel.toggleVisibility("eventLog")
                    },
                    QuickAction(label: "History", icon: "clock.arrow.circlepath", tint: SPAIColor.secondary) {
                        appModel.toggleVisibility("history")
                    },
                    QuickAction(label: "Reset", icon: "arrow.clockwise", tint: SPAIColor.critical) {
                        appModel.resetWorkflow()
                    }
                ])
            }
            Attachment(id: "report") { SessionReportPanel() }
            Attachment(id: "guided") { GuidedStepPanel() }
            Attachment(id: "history") { SessionHistoryPanel() }
            Attachment(id: "wristMenu") {
                // Right wrist: quick actions, summoned by turning the wrist toward you.
                WristMenuPanel(isPresented: handTracking.rightWristPresented)
            }
            Attachment(id: "stationPicker") {
                // Left forearm: station picker, summoned by holding the forearm level.
                StationPickerPanel(
                    manager: stationManager,
                    compact: true,
                    isPresented: handTracking.leftWristPresented
                )
            }
            Attachment(id: "tour") { TourCoachmark() }
        }
    }

    /// Parks the tour card just inside the panel it is describing — nearer to the user and
    /// nudged off-centre so it never sits on top of its own subject.
    private func tourPosition() -> SIMD3<Float> {
        let anchor = appModel.tour.anchor

        if anchor == .wristMenu {
            // Float beside the wrist rather than at the arc slot, so "tap Chat on your wrist"
            // is readable while the user is actually looking at their arm.
            if let pose = handTracking.rightWristPose {
                let right = normalize(cross(pose.up, pose.forward))
                return pose.position + right * 0.30 + pose.up * 0.28
            }
            return arcPosition(for: "wristMenu") + SIMD3<Float>(0, 0.35, 0.15)
        }

        guard anchor != .center, let slot = Self.layout[anchor.rawValue] else {
            // Straight ahead, a little below the eye line.
            return [0, headAnchor.eyeHeight - 0.12, -1.0]
        }

        // Same bearing as the subject, pulled 0.3 m closer and dropped slightly so the card
        // reads as sitting in front of the panel it points at.
        let a = slot.angle * .pi / 180
        let radius = max(slot.radius - 0.30, 0.65)
        let y = headAnchor.eyeHeight + slot.heightAboveEye - 0.22
        return [radius * sin(a), y, -radius * cos(a)]
    }

    /// World position for a panel's slot, with heights resolved against the wearer's measured
    /// eye line.
    private func arcPosition(for id: String) -> SIMD3<Float> {
        guard let slot = Self.layout[id] else {
            return [0, headAnchor.eyeHeight, -arcRadius]
        }
        let a = slot.angle * .pi / 180
        let y = headAnchor.eyeHeight + slot.heightAboveEye
        return [slot.radius * sin(a), y, -slot.radius * cos(a)]
    }

    private func place(
        _ id: String,
        _ content: RealityViewContent,
        _ attachments: RealityViewAttachments
    ) {
        guard let panel = attachments.entity(for: id) else { return }
        panel.position = arcPosition(for: id)
        applyBillboard(to: panel)
        content.add(panel)
    }

    private func setEnabled(_ id: String, _ attachments: RealityViewAttachments) {
        attachments.entity(for: id)?.isEnabled = appModel.isVisible(id)
    }

    /// Scales a newly-opened panel up from the wrist menu into its slot. The tester tapped
    /// History and concluded nothing happened, because the panel simply blinked into
    /// existence off to one side. Motion out of the button gives the eye something to follow.
    private func animateEntrance(_ id: String, _ attachments: RealityViewAttachments) {
        guard let panel = attachments.entity(for: id) else { return }
        let home = arcPosition(for: id)

        // Reduce Motion: land the panel in place. The wrist menu's written confirmation
        // ("History opened") still says what happened, so nothing is lost but the flight.
        guard !reduceMotion else {
            panel.position = home
            panel.scale = .one
            return
        }

        let source = attachments.entity(for: "wristMenu")?.position ?? home

        panel.position = source
        panel.scale = SIMD3<Float>(repeating: 0.2)

        let target = Transform(
            scale: .one,
            rotation: panel.orientation,
            translation: home
        )
        // Slight overshoot so the panel lands with a bit of weight rather than easing to a stop.
        panel.move(
            to: target,
            relativeTo: panel.parent,
            duration: 0.45,
            timingFunction: .cubicBezier(
                controlPoint1: SIMD2<Float>(0.2, 0.9),
                controlPoint2: SIMD2<Float>(0.25, 1.06)
            )
        )
    }

    /// Re-anchors a wrist panel to the live tracked wrist pose each frame. Falls back to a fixed
    /// room position (used at `place()` time too) whenever there's no pose to track — in the
    /// simulator, where hand tracking never runs, or on device before/between hand detections.
    private func updateWristAnchor(
        _ id: String,
        _ attachments: RealityViewAttachments,
        pose: (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)?,
        offset: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) {
        guard let panel = attachments.entity(for: id) else { return }
        #if targetEnvironment(simulator)
        panel.position = fallback
        #else
        guard let pose else {
            // Hold the last position while the panel fades out. Snapping back to the fixed
            // fallback would send it flying across the room mid-fade; the fallback is only
            // for the very first frame, before either wrist has ever been seen.
            if panel.position == .zero { panel.position = fallback }
            return
        }
        let right = normalize(cross(pose.up, pose.forward))
        panel.position = pose.position + right * offset.x + pose.up * offset.y + pose.forward * offset.z
        #endif
    }
    
    private func updateBillboard(_ id: String, _ attachments: RealityViewAttachments) {
        guard let entity = attachments.entity(for: id) else { return }
        applyBillboard(to: entity)
    }

    /// Keeps the tour card beside whatever the current step is about, gliding between subjects
    /// so the user's eye is led from one panel to the next instead of the card teleporting.
    private func updateTourCard(_ attachments: RealityViewAttachments) {
        guard let card = attachments.entity(for: "tour") else { return }

        card.isEnabled = appModel.tour.isVisible
        guard appModel.tour.isVisible else {
            // Forget the anchor so a replayed tour re-runs its entrance and picks up a
            // fresh eye-height calibration rather than reusing a stale position.
            entranceLog.tourAnchor = nil
            return
        }

        // The card must always face the user, whatever the panel billboard setting is —
        // it is a piece of instruction, not a workspace panel.
        var billboard = BillboardComponent()
        billboard.blendFactor = 1.0
        card.components.set(billboard)

        let target = tourPosition()
        let anchorKey = appModel.tour.anchor.rawValue

        if entranceLog.tourAnchor != anchorKey {
            let isFirstPlacement = entranceLog.tourAnchor == nil
            entranceLog.tourAnchor = anchorKey

            if reduceMotion {
                card.position = target
                card.scale = .one
            } else if isFirstPlacement {
                card.position = target
                card.scale = SIMD3<Float>(repeating: 0.3)
                card.move(
                    to: Transform(scale: .one, rotation: card.orientation, translation: target),
                    relativeTo: card.parent,
                    duration: 0.45,
                    timingFunction: .easeOut
                )
            } else {
                card.move(
                    to: Transform(scale: .one, rotation: card.orientation, translation: target),
                    relativeTo: card.parent,
                    duration: 0.6,
                    timingFunction: .easeInOut
                )
            }
        } else if appModel.tour.anchor == .wristMenu {
            // The wrist moves continuously, so track it rather than animating to a fixed point.
            card.position = target
        }
    }

    /// `BillboardComponent` carries a `blendFactor` that controls how much of the billboard
    /// rotation is actually applied. The old code constructed the component with `init()` and
    /// never set it, which is why "Panels look at you" appeared wired up — the setting really
    /// did add and remove the component — while nothing visibly turned to face the user.
    private func applyBillboard(to entity: Entity) {
        if appModel.panelsBillboard {
            var billboard = BillboardComponent()
            billboard.blendFactor = 1.0
            entity.components.set(billboard)
        } else {
            entity.components.remove(BillboardComponent.self)
        }
    }
}

/// Tracks which panel-open event the entrance animation has already played, so the RealityView
/// update closure runs it exactly once. Deliberately a reference type held in `@State`: writing
/// to it must not invalidate the view, or the update closure would retrigger itself forever.
@MainActor
final class PanelEntranceLog {
    var handledAt: Date?
    /// Anchor the tour card was last moved to, so it only animates when the subject changes.
    var tourAnchor: String?
    /// Eye height the arc was last laid out against, so calibration is applied exactly once.
    var appliedEyeHeight: Float?
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}

