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

///
/// All panels and controls in this immersive space should use the shared `panelWidth`
/// for frames, font sizes, button heights, padding, and spacing. This ensures a single
/// cohesive proportional sizing system across the app.
///
/// All interactive controls (buttons) must enforce min hit area with `.spaiHitTarget(minSize: max(44, panelWidth * 0.13), pop: 1.08)`
/// or equivalent. Visual size and hit area must be proportional to `panelWidth` everywhere.
///
struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(DetectionService.self) private var detectionService
    @State private var stationManager = StationManager()

    @State private var cameraService = CameraFrameService()
    @State private var handTracking = HandTrackingService()
    @State private var headAnchor = HeadAnchorService()

    @State private var cameraUnavailable: Bool = false
    @State private var cameraErrorMessage: String? = nil

    /// Not `@State`: this is bookkeeping for the entrance animation, and mutating it must not
    /// invalidate the view — doing that from inside a RealityView update closure would loop.
    @State private var entranceLog = PanelEntranceLog()

    private let arcRadius: Float = 1.25

    /// Shared panel width for consistent proportional sizing
    // Each panel receives its own width from SPAILayout so the whole arc scales from
    // one place. See DesignTokens.swift for the rationale behind each value.
    // Update this value to adjust all panel and content sizing proportionally

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
        ZStack {
            realityContent

            if let cameraErrorMessage, cameraUnavailable {
                VStack {
                    Spacer()
                    Text(cameraErrorMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .padding()
                }
                .transition(.opacity)
            }
        }
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
            // SCRUM-80 / SCRUM-114: the AVP main camera feeds live frames into
            // DetectionService via CameraFrameService, which now applies two filters
            // before calling onFrameForDetection:
            //
            //   1. Head-stability gate — frames are skipped while the head is moving
            //      (yaw change > DetectionTuning.headYawThresholdDegrees), so a brief
            //      glance to the side doesn't trigger detection on whatever happens to
            //      be centred at that moment.
            //
            //   2. Zone crop — only the central passthrough rectangle (the "clear space"
            //      between the arc panels) is sent to detection, not the full ~90° FoV.
            //      Peripheral objects that never enter the work area are invisible to the
            //      detection pipeline.
            //
            // The callback receives a ready UIImage (already cropped and converted); no
            // pixel-buffer handling is needed here.
            //
            // Main Camera Access is an Enterprise entitlement — CameraFrameService.start()
            // handles auth failure gracefully (logs, leaves the workflow unaffected).
            cameraService.headYawProvider = { headAnchor.currentHeadYaw() }
            cameraService.onFrameForDetection = { image in
                // Pass both the station step and the current guided sub-step condition so
                // DetectionService can gate to exactly the inference this sub-step needs.
                // A .manual sub-step produces a nil condition → full early-exit in detect().
                let step = SterileStep(rawValue: appModel.currentStepIndex)
                let guidedCondition = appModel.currentGuidedStepCondition
                Task { await detectionService.detect(image: image, step: step, guidedCondition: guidedCondition) }
            }
            await cameraService.start()

            // Check if camera started. If not, fallback to picker/upload panel.
            cameraUnavailable = !cameraService.isRunning
            cameraErrorMessage = cameraService.statusMessage
        }
        #endif
        // Entering the workflow dismisses the "home" window, which takes RootSceneView — and
        // its scene-phase observer — with it. Without this, the main path into the app is
        // exactly the path where nothing is left to tear the immersive space down, which is
        // how immersive content ended up outliving the app during testing.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            Task { @MainActor in
                if(appModel.immersiveSpaceState == .open){
                    await dismissImmersiveSpace()
                }
                appModel.immersiveSpaceState = .closed
            }
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            // Clear all drag offsets so the next session starts from the default arc layout.
            appModel.resetAllDragOffsets()
            #if !targetEnvironment(simulator)
            cameraService.stop()
            #endif
            headAnchor.stop()
            appModel.tour.stop()
            SoundManager.shared.contaminationAnchor = nil
            SpeechManager.shared.guidedAnchor = nil
            // The home window was dismissed when the user entered the workflow.
            // Reopen it now so there is always a window to return to when the
            // immersive space closes (crown press, app relaunch, background, etc.).
            openWindow(id: "home")
        }
    }
    
    private var realityContent: some View {
        RealityView { content, attachments in
            // The placeholder "Immersive" environment from the RealityKitContent package is
            // deliberately not loaded. It is an opaque skybox, so it replaces passthrough with
            // a black room — the workspace is meant to sit over the real one. Restore this once
            // there is a real environment authored in Reality Composer Pro.

            for id in Self.layout.keys {
                
                place(id, content, attachments)
            }

            // The tour card has no fixed slot — it moves to whichever panel is being
            // explained — so it is not in `layout` and has to be added to the scene here.
            if let tourCard = attachments.entity(for: "tour") {
                tourCard.isEnabled = false
                content.add(tourCard)
            }

            // The soft-interrupt popup floats near whichever panel the user just tapped
            // while the tour was waiting on a different action.
            if let interruptPopup = attachments.entity(for: "tourInterrupt") {
                interruptPopup.isEnabled = false
                content.add(interruptPopup)
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
            #if targetEnvironment(simulator)
            setEnabled("upload", attachments)
            #endif
            setEnabled("actions", attachments)

            // The wrist panels stay enabled and fade themselves out when tracking drops.
            // Disabling the entity the moment the pose went nil would cut the fade off
            // mid-animation and read as the same abrupt pop the freeze did.
            attachments.entity(for: "stationPicker")?.isEnabled = true
            attachments.entity(for: "wristMenu")?.isEnabled = true

            // Apply drag offsets in real-time while the user moves a panel handle.
            // Reading appModel.panelDragOffsets here registers it as an Observable dependency,
            // so the update closure re-runs whenever any offset changes during a drag gesture.
            // Guard: skip wrist panels (repositioned by wrist anchors) and mid-animation ones.
            for id in Self.layout.keys
            where id != "wristMenu" && id != "stationPicker" && !entranceLog.isAnimating(id) {
                guard appModel.dragOffset(for: id) != .zero else { continue }
                attachments.entity(for: id)?.position = effectivePosition(for: id)
            }

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
                for id in Self.layout.keys
                where id != "wristMenu" && id != "stationPicker" && !entranceLog.isAnimating(id) {
                    // effectivePosition = arcPosition + any drag offset the user has applied,
                    // so recalibration doesn't snap a repositioned panel back to the arc.
                    attachments.entity(for: id)?.position = effectivePosition(for: id)
                }

                // Diagnostic. The arc is laid out against `headAnchor.eyeHeight`, which is read
                // from ARKit's world space, while the panels live in the RealityView's scene
                // space. If those two do not share an origin, the arc lands at the wrong height
                // whatever the measurement says — and "on the floor" followed by "above my
                // head" is what a space mismatch looks like from the inside. Print the head,
                // the applied height, and where a panel actually ended up, to settle it.
                let head = headAnchor.currentHeadPosition()
                let headText = head.map { "[\($0.x), \($0.y), \($0.z)]" } ?? "nil"
                let calibratedText = headAnchor.calibratedEyeHeight.map { "\($0)" } ?? "nil"
                SPAILog.info(.ui, "arc relaid — applied eyeHeight \(headAnchor.eyeHeight) m, calibrated \(calibratedText), live head \(headText)")
                for id in ["statusBar", "workflow", "detection"] {
                    if let e = attachments.entity(for: id) {
                        let w = e.position(relativeTo: nil)
                        SPAILog.info(.ui, "  \(id) world [\(w.x), \(w.y), \(w.z)]")
                    }
                }
            }

            attachments.entity(for: "report")?.isEnabled = appModel.sessionComplete
            attachments.entity(for: "guided")?.isEnabled =
                appModel.stepStarted && !appModel.sessionComplete && appModel.canRunWorkflow

            // Every pass, not only when the setting changes: this now writes an orientation
            // that depends on where the user's head is, so it goes stale as they move. It is
            // a quaternion per panel rather than the component write it replaced, which is
            // what made doing this every pass too expensive before.
            //
            // Skip a panel still mid-`animateEntrance`: writing orientation directly onto an
            // entity `move(to:)` is animating interrupts that animation on the spot, the same
            // failure `updateTourCard` already documents for the tour card. Uncaught here it
            // stranded regular panels mid-flight — at a random point along the 0.45 s tween,
            // sometimes still scaled down from the entrance — which is why a reopened panel
            // could land somewhere wrong or, after enough interrupted replays, never visibly
            // recover its scale at all.
            for id in Self.layout.keys where !entranceLog.isAnimating(id) {
                updateFacing(id, attachments)
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
            // Keep the tour card facing the user on every frame once its entrance animation
            // completes — the same per-frame pattern that regular panels use via the
            // `Self.layout.keys` loop above. "tour" is not in that dict, so it was never
            // included, which is why the card froze at the heading it had when the animation
            // started and drifted as the user moved their head.
            //
            // The wristMenu anchor already handles its own per-frame facing inside
            // updateTourCard (it must follow a live wrist pose), so skip it here.
            //
            // Guard against isTourAnimating for the same reason the regular-panel loop
            // guards against entranceLog.isAnimating: writing orientation directly while
            // move(to:) is running cancels its rotation track on the spot.
            if appModel.tour.isVisible,
               appModel.tour.anchor != .wristMenu,
               !entranceLog.isTourAnimating,
               let tourCard = attachments.entity(for: "tour"),
               let head = headAnchor.currentHeadPosition() {
                face(tourCard, towards: head)
            }
            // updateTourInterrupt(attachments)
        } attachments: {
            Attachment(id: "statusBar") { StatusBarPanel(panelWidth: SPAILayout.barWidth) }
            Attachment(id: "detection") { DetectionPanel(service: detectionService, panelWidth: SPAILayout.standardWidth) }
            Attachment(id: "eventLog")  { EventLogPanel(panelWidth: SPAILayout.standardWidth) }
            Attachment(id: "workflow")  { WorkflowProgressPanel(panelWidth: SPAILayout.wideWidth) }
            // Simulator only: image-picker upload panel.
            // On device the ARKit main camera (CameraFrameService) feeds detection
            // automatically — DetectionUploadPanel must not exist in the view hierarchy.
            #if targetEnvironment(simulator)
            Attachment(id: "upload")   { DetectionUploadPanel(service: detectionService, panelWidth: SPAILayout.compactWidth) }
            #endif
            Attachment(id: "chat") { ChatPanel(panelWidth: SPAILayout.chatWidth) }
            Attachment(id: "actions") {
                // TODO: Use panelWidth for all layout, padding, and sizing in this panel.
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
            Attachment(id: "report") { SessionReportPanel(panelWidth: SPAILayout.standardWidth) }
            Attachment(id: "guided") { GuidedStepPanel(panelWidth: SPAILayout.standardWidth) }
            Attachment(id: "history") { SessionHistoryPanel(panelWidth: SPAILayout.standardWidth) }
            Attachment(id: "wristMenu") {
                // Right wrist: quick actions, summoned by turning the wrist toward you.
                // TODO: Use panelWidth for all layout, padding, and sizing in this panel.
                WristMenuPanel(isPresented: handTracking.rightWristPresented)
            }
            Attachment(id: "stationPicker") {
                // Left forearm: station picker, summoned by holding the forearm level.
                // TODO: Use panelWidth for all layout, padding, and sizing in this panel.
                StationPickerPanel(
                    manager: stationManager,
                    compact: true,
                    isPresented: handTracking.leftWristPresented
                )
            }
            Attachment(id: "tour") { TourCoachmark() }
            Attachment(id: "tourInterrupt") { TourInterruptPopup() }
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
            // No wrist tracking (simulator, or wrist not yet seen on device).
            //
            // The old fallback was arcPosition(for: "wristMenu") + (0, 0.35, 0.15), which
            // placed the card at x ≈ −1.13 m (far left) and z ≈ −0.26 m (very close).
            // At that distance a 420-pt card fills most of the viewport and looks broken.
            // Float straight ahead at normal reading distance instead — the wrist steps don't
            // need a specific panel anchor, they just need to be readable.
            SPAILog.debug(.ui, "tour wristMenu — no wrist pose, using centre fallback")
            return [0, headAnchor.eyeHeight - 0.10, -1.20]
        }

        guard anchor != .center, let slot = Self.layout[anchor.rawValue] else {
            // Straight ahead, a little below the eye line.
            return [0, headAnchor.eyeHeight - 0.12, -1.0]
        }

        // Same bearing as the subject, pulled 0.3 m closer.
        //
        // The card normally drops 0.22 m below the panel centre so it reads as a caption.
        // Exception: the workflow panel is already low (-0.65 m) and its controls — including
        // the Start Step button the tour step tells the user to tap — sit at the panel's
        // bottom edge. A -0.22 offset would place the card (at z = -0.85, closer than the
        // panel) in front of those controls, making them unreachable while the tour is on
        // that step. Position the card 0.20 m ABOVE the workflow panel centre instead, so
        // the step-node track is behind the card but the control row is fully clear.
        let a = slot.angle * .pi / 180
        let radius = max(slot.radius - 0.30, 0.65)
        let yOffset: Float = (anchor == .workflow) ? 0.20 : -0.22
        let y = headAnchor.eyeHeight + slot.heightAboveEye + yOffset
        return [radius * sin(a), y, -radius * cos(a)]

    }
    /// Arc position plus any drag offset the user has accumulated this session.
    ///
    /// Every code path that places or repositions a panel should call this rather than
    /// `arcPosition(for:)` directly so that a dragged panel doesn't snap back to centre
    /// on the next eye-height recalibration or entrance animation.
    private func effectivePosition(for id: String) -> SIMD3<Float> {
        arcPosition(for: id) + appModel.dragOffset(for: id)
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
        panel.components.set(InputTargetComponent())
        
        panel.position = arcPosition(for: id)
        applyFacing(to: panel)
        content.add(panel)
    }

    private func setEnabled(_ id: String, _ attachments: RealityViewAttachments) {
        attachments.entity(for: id)?.isEnabled =  appModel.isVisible(id)
    }

    /// Scales a newly-opened panel up from the wrist menu into its slot. The tester tapped
    /// History and concluded nothing happened, because the panel simply blinked into
    /// existence off to one side. Motion out of the button gives the eye something to follow.
    private func animateEntrance(_ id: String, _ attachments: RealityViewAttachments) {
        guard let panel = attachments.entity(for: id) else { return }
        // If the panel has been dragged this session, fly to its dragged position rather
        // than the arc position so it lands where the user left it.
        let home = effectivePosition(for: id)

        // Face the user once, before the flight starts, rather than leaving `updateFacing`
        // to do it mid-animation — see the skip-while-animating note where that loop calls
        // `entranceLog.isAnimating(id)`.
        if let head = headAnchor.currentHeadPosition() {
            face(panel, towards: head)
        }

        // Reduce Motion: land the panel in place. The wrist menu's written confirmation
        // ("History opened") still says what happened, so nothing is lost but the flight.
        guard !reduceMotion else {
            panel.position = home
            panel.scale = .one
            entranceLog.inFlight[id] = nil
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
        // The returned controller is what lets `updateFacing` and the eye-height reposition
        // block (both of which write the transform directly) know to leave this panel alone
        // until the flight actually finishes — a direct write while `move()` is still running
        // interrupts it on the spot, stranding the panel wherever it was mid-flight.
        entranceLog.inFlight[id] = panel.move(
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
    
    private func updateFacing(_ id: String, _ attachments: RealityViewAttachments) {
        guard let entity = attachments.entity(for: id) else { return }
        applyFacing(to: entity)
    }

    /// Keeps the tour card above whatever the current step is about, gliding between subjects
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

        let target = tourPosition()
        let anchorKey = appModel.tour.anchor.rawValue

        if entranceLog.tourAnchor != anchorKey {
            let isFirstPlacement = entranceLog.tourAnchor == nil
            entranceLog.tourAnchor = anchorKey

            // Orient the card toward the user once, just before the animation starts.
            // Calling face() on every update pass was the root cause of the "trippy"
            // animation: setOrientation conflicts with a running move() animation, causing
            // the card to stutter or stop mid-flight at a wrong position.
            card.components.remove(BillboardComponent.self)
            if let head = headAnchor.currentHeadPosition() {
                face(card, towards: head)
            }

            if reduceMotion {
                card.position = target
                card.scale = .one
            } else if isFirstPlacement {
                card.position = target
                card.scale = SIMD3<Float>(repeating: 0.3)
                entranceLog.tourAnimController = card.move(
                    to: Transform(scale: .one, rotation: card.orientation, translation: target),
                    relativeTo: card.parent,
                    duration: 0.45,
                    timingFunction: .easeOut
                )
            } else {
                entranceLog.tourAnimController = card.move(
                    to: Transform(scale: .one, rotation: card.orientation, translation: target),
                    relativeTo: card.parent,
                    duration: 0.6,
                    timingFunction: .easeInOut
                )
            }
        } else if appModel.tour.anchor == .wristMenu {
            // Follow the wrist every frame when tracking is live.
            //
            // IMPORTANT: only write card.position when there is an actual wrist pose to
            // follow. Setting position unconditionally — even to the same fallback value —
            // cancels any running move(to:) animation on the very next update pass, because
            // RealityKit treats a direct property write as "the animation is done". The
            // entrance animation (0.3 → 1.0 scale) is fired once in the if-block above; if
            // we stomp it here every frame the card stays at scale 0.3 and looks tiny.
            if handTracking.rightWristPose != nil {
                card.position = target
                card.components.remove(BillboardComponent.self)
                if let head = headAnchor.currentHeadPosition() {
                    face(card, towards: head)
                }
            }
            // No wrist pose: the card stays wherever the entrance animation left it (the
            // centre fallback from tourPosition). Nothing to update.
        }
    }

    /// Arc position for the soft-interrupt popup — near the panel the user just tapped
    /// rather than near the current tour step's panel.
    private func interruptPosition() -> SIMD3<Float> {
        guard let anchorID = appModel.tour.interruptAnchorID,
              let slot = Self.layout[anchorID] else {
            return [0, headAnchor.eyeHeight - 0.05, -1.0]
        }
        // Slightly closer to the user than the panel (0.15 m) and above its centre
        // (0.25 m) so the popup reads as a foreground notification layered over the
        // place the user was just looking.
        let a = slot.angle * .pi / 180
        let radius = max(slot.radius - 0.15, 0.60)
        let y = headAnchor.eyeHeight + slot.heightAboveEye + 0.25
        return [radius * sin(a), y, -radius * cos(a)]
    }

    /// Shows, hides, and repositions the soft-interrupt popup each RealityView pass.
    ///
    /// Unlike the tour card, the popup is deliberately NOT animated with `move(to:)` —
    /// it snaps into place so the user's attention is grabbed immediately, and the
    /// SwiftUI transition handles the appear/disappear animation.
    private func updateTourInterrupt(_ attachments: RealityViewAttachments) {
        guard let popup = attachments.entity(for: "tourInterrupt") else { return }

        let isVisible = appModel.tour.interruptAnchorID != nil
        popup.isEnabled = isVisible
        guard isVisible else { return }

        // Snap to position — no move() animation, the SwiftUI transition is enough.
        popup.position = interruptPosition()

        // Face the user. Calling face() every frame is fine here: the interrupt is
        // brief (3.5 s max) and has no long-running move() animation to fight.
        popup.components.remove(BillboardComponent.self)
        if let head = headAnchor.currentHeadPosition() {
            face(popup, towards: head)
        }
    }

    /// Turns a panel to face the user by writing its **orientation**, not by attaching a
    /// `BillboardComponent`.
    ///
    /// This is the whole reason nothing in the workspace was tappable on device.
    ///
    /// `BillboardComponent` rotates a panel at render time and leaves the entity's transform
    /// alone — but the region that accepts a tap is derived from that transform. Panels are
    /// placed by `arcPosition` with a position only, so their orientation stays at identity
    /// (facing -Z, straight down the room's forward axis). Once `blendFactor` was set to 1.0
    /// in SCRUM-122 the panels visibly turned toward the user while their tappable regions
    /// stayed pointing wherever they were authored, and a tap landed on nothing. The further
    /// off the centre line a panel sat, the wider the miss: `chat` at +46°, `actions` at +54°.
    /// The floor-level eye height from the calibration bug piled a large pitch error on top.
    ///
    /// It also explains the one control that did work: the tour card sits dead ahead at
    /// `.center`, where the billboard rotation is close to zero, so its visual and its hit
    /// region still coincided and "Skip tour" was tappable while nothing else was.
    ///
    /// Writing the orientation keeps the two in the same place, because there is only one of
    /// them. Slightly more work per pass than a component the render loop applies for free —
    /// a quaternion per panel — and worth it for panels that respond when pressed.
    private func applyFacing(to entity: Entity) {
        // Belt and braces: if any of these entities is carrying the old component, the render
        // rotation would fight the orientation written below.
        entity.components.remove(BillboardComponent.self)

        guard appModel.panelsBillboard, let head = headAnchor.currentHeadPosition() else {
            // Straight ahead — identity is what the panels used before SCRUM-122, and what
            // the simulator still uses, since there is no device pose to face there.
            entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            return
        }
        face(entity, towards: head)
    }

    /// Aims `entity`'s front at `head`, writing **only** the orientation.
    ///
    /// The first version of this used `look(at:from:relativeTo:)`, which writes position as
    /// well. That fought the `move(to:)` animations in `animateEntrance` and `updateTourCard`
    /// — the transform was being reset underneath a running animation on every update pass —
    /// and it is why the tour card stopped appearing when the tour started. Orientation is the
    /// only thing this needs to change; positions belong to the arc and to the animations.
    private func face(_ entity: Entity, towards head: SIMD3<Float>) {
        let toHead = head - entity.position(relativeTo: nil)
        guard length_squared(toHead) > 1e-6 else { return }
        let dir = normalize(toHead)

        // A head directly above or below a panel makes the up vector degenerate and the
        // resulting rotation NaN — which renders as nothing at all. Leave the panel as it is
        // rather than make it vanish.
        guard abs(dir.y) < 0.999 else { return }

        // An attachment's content faces +Z, so build the rotation carrying +Z onto `dir`.
        let rotation = simd_quatf(angle: atan2(dir.x, dir.z), axis: [0, 1, 0])
                     * simd_quatf(angle: -asin(dir.y), axis: [1, 0, 0])
        entity.setOrientation(rotation, relativeTo: nil)
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

    /// One entry per panel currently mid-`animateEntrance`. Anything that writes a panel's
    /// transform directly — `updateFacing`'s per-pass orientation write, the eye-height
    /// reposition block — has to check this first: a direct write while `move(to:)` is still
    /// running interrupts that animation immediately, leaving the panel wherever it happened
    /// to be, sometimes still scaled down from the entrance. `AnimationPlaybackController` is
    /// the actual RealityKit source of truth for "is this still running," rather than a
    /// duplicated timer that would drift if `animateEntrance`'s duration ever changed.
    ///
    /// Bounded by the fixed panel count (12) — one entry per id, always overwritten by the
    /// next `animateEntrance` call for that id — so nothing here needs explicit eviction.
    var inFlight: [String: AnimationPlaybackController] = [:]

    /// The most recent `move(to:)` controller for the tour card. Stored so the per-frame
    /// orientation update can be skipped while the card is still in flight — writing
    /// orientation directly during a running `move()` cancels its rotation track and strands
    /// the card mid-flight (the same failure documented in `updateTourCard`). Once the
    /// controller reports `.isComplete`, per-frame facing resumes.
    var tourAnimController: AnimationPlaybackController?

    func isAnimating(_ id: String) -> Bool {
        guard let controller = inFlight[id] else { return false }
        return !controller.isComplete
    }

    var isTourAnimating: Bool {
        guard let c = tourAnimController else { return false }
        return !c.isComplete
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
