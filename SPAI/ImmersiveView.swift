//
//  ImmersiveView.swift
//  SPAI
//

import SwiftUI
import RealityKit
import RealityKitContent
import simd

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(DetectionService.self) private var detectionService
    @State private var stationManager = StationManager()

    @State private var cameraService = CameraFrameService()
    @State private var showInteractiveOnboarding: Bool = false
    @State private var handTracking = HandTrackingService()

    private let arcRadius: Float = 1.25

    var body: some View {
        ZStack {
            realityContent
            
            // Interactive onboarding overlay
            if showInteractiveOnboarding {
                InteractiveOnboardingView(isActive: $showInteractiveOnboarding)
                    .transition(.opacity)
            }
        }
        .onAppear {
            appModel.immersiveSpaceState = .open
            
            // Show interactive tour if first time
            if !appModel.hasCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation {
                        showInteractiveOnboarding = true
                    }
                }
            }
            
            stationManager.onEnter = { station in
                appModel.currentStepIndex = station.step.rawValue
                appModel.stepStarted = false
                appModel.logStationEntry(station.name, step: station.step)
            }
            #if !targetEnvironment(simulator)
            Task { await stationManager.startImageTracking() }
            Task { await handTracking.start() }
            #endif
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
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            #if !targetEnvironment(simulator)
            cameraService.stop()
            #endif
            SoundManager.shared.contaminationAnchor = nil
            SpeechManager.shared.guidedAnchor = nil
        }
    }
    
    private var realityContent: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            place("statusBar", angle: 0, height: 1.9, radius: 1.3, content, attachments)

            place("detection", angle: -30, height: 1.45, radius: 1.2, content, attachments)
            place("eventLog",  angle:  30, height: 1.45, radius: 1.2, content, attachments)
            if let detectionEntity = attachments.entity(for: "detection") {
                detectionEntity.spatialAudio = SpatialAudioComponent()
                SoundManager.shared.contaminationAnchor = detectionEntity
            }

            place("guided",    angle:  16, height: 1.15, radius: 1.15, content, attachments)
            if let guidedEntity = attachments.entity(for: "guided") {
                guidedEntity.spatialAudio = SpatialAudioComponent()
                SpeechManager.shared.guidedAnchor = guidedEntity
            }

            place("workflow",  angle:  0,  height: 0.85, radius: 1.1, content, attachments)
            // Removed: camera panel (merged into upload window)
            // place("camera",    angle: -16, height: 1.15, radius: 1.15, content, attachments)

            place("actions",   angle:  52, height: 1.25, radius: 1.3, content, attachments)
            place("chat",      angle:  48, height: 1.7,  radius: 1.3, content, attachments)
            place("history",   angle: -52, height: 1.55, radius: 1.3, content, attachments)
            place("wristMenu", angle: -70, height: 0.9, radius: 1.2, content, attachments)
            place("stationPicker", angle: -30, height: 0.85, radius: 1.2, content, attachments)

            place("report",    angle:  0,  height: 1.4,  radius: 1.05, content, attachments)

            #if true
            place("upload",    angle: -52, height: 1.0,  radius: 1.3, content, attachments)
            #endif
        } update: { _, attachments in
            setEnabled("statusBar", attachments)
            setEnabled("detection", attachments)
            setEnabled("eventLog",  attachments)
            setEnabled("workflow",  attachments)
            // Removed: camera panel
            // setEnabled("camera", attachments)
            setEnabled("chat", attachments)
            setEnabled("history", attachments)
            // setEnabled("wristMenu", attachments) // Not explicitly enabled here, but not changed per instructions
            #if targetEnvironment(simulator)
            attachments.entity(for: "stationPicker")?.isEnabled = true
            #else
            attachments.entity(for: "stationPicker")?.isEnabled = handTracking.leftWristPose != nil
            #endif

            updateWristAnchor(
                "wristMenu", attachments,
                pose: handTracking.rightWristPose,
                offset: SIMD3<Float>(x: 0.06, y: 0.025, z: -0.02),
                fallback: arcPosition(angle: -70, height: 0.9, radius: 1.2)
            )
            updateWristAnchor(
                "stationPicker", attachments,
                pose: handTracking.leftWristPose,
                offset: SIMD3<Float>(x: -0.06, y: 0.025, z: -0.02),
                fallback: arcPosition(angle: -30, height: 0.85, radius: 1.2)
            )
            attachments.entity(for: "report")?.isEnabled = appModel.sessionComplete
            attachments.entity(for: "guided")?.isEnabled = appModel.stepStarted && !appModel.sessionComplete && appModel.canRunWorkflow
            
            // Update billboard state for all panels
            updateBillboard("statusBar", attachments)
            updateBillboard("detection", attachments)
            updateBillboard("eventLog", attachments)
            updateBillboard("workflow", attachments)
            // Removed: camera panel
            // updateBillboard("camera", attachments)
            updateBillboard("guided", attachments)
            updateBillboard("actions", attachments)
            updateBillboard("chat", attachments)
            updateBillboard("history", attachments)
            // Removed updateBillboard("wristMenu", attachments)
            updateBillboard("stationPicker", attachments)
            updateBillboard("report", attachments)
            #if true
            updateBillboard("upload", attachments)
            #endif
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
                // Right wrist (or simulator fallback): quick-action menu
                WristMenuPanel(
                    isHandVisibleProvider: {
                        handTracking.rightWristPosition != nil
                    }
                )
            }
            Attachment(id: "stationPicker") {
                // Left wrist: compact station picker
                StationPickerPanel(manager: stationManager, compact: true)
            }
        }
    }

    private func arcPosition(angle degrees: Float, height: Float, radius: Float) -> SIMD3<Float> {
        let a = degrees * .pi / 180
        return [radius * sin(a), height, -radius * cos(a)]
    }

    private func place(
        _ id: some Hashable,
        angle: Float,
        height: Float,
        radius: Float? = nil,
        _ content: RealityViewContent,
        _ attachments: RealityViewAttachments
    ) {
        guard let panel = attachments.entity(for: id) else { return }
        panel.position = arcPosition(angle: angle, height: height, radius: radius ?? arcRadius)
        
        // Only add billboard if enabled in settings
        if appModel.panelsBillboard {
            panel.components.set(BillboardComponent())
        } else {
            panel.components.remove(BillboardComponent.self)
        }
        
        content.add(panel)
    }

    private func setEnabled(_ id: String, _ attachments: RealityViewAttachments) {
        attachments.entity(for: id)?.isEnabled = appModel.isVisible(id)
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
            panel.position = fallback
            return
        }
        let right = normalize(cross(pose.up, pose.forward))
        panel.position = pose.position + right * offset.x + pose.up * offset.y + pose.forward * offset.z
        #endif
    }
    
    private func updateBillboard(_ id: String, _ attachments: RealityViewAttachments) {
        guard let entity = attachments.entity(for: id) else { return }
        if appModel.panelsBillboard {
            entity.components.set(BillboardComponent())
        } else {
            entity.components.remove(BillboardComponent.self)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}

