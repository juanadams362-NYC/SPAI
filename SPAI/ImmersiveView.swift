//
//  ImmersiveView.swift
//  SPAI
//
//  The spatial workspace. Panels sit on a cockpit arc: every panel at the
//  same radius from the user, positioned by angle + height instead of
//  hand-typed xyz. Center of the arc at eye level stays empty — that's
//  the work zone. Negative angle = left of center, positive = right.
//
//  On hardware, the main camera feeds live frames into DetectionService.
//  Camera access only works inside an ImmersiveSpace, which is exactly here.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(DetectionService.self) private var detectionService
    @State private var stationManager = StationManager()

    // Live camera feed. Hardware-only — on the sim this object just sits idle
    // (its start() denies cleanly without the entitlement / a real camera).
    @State private var cameraService = CameraFrameService()

    // One radius for the whole cockpit. Change this to pull the entire
    // arc closer or push it away — everything stays consistent.
    private let arcRadius: Float = 1.25

    var body: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            // Top rail: status bar above the sightline, dead center.
            place("statusBar", angle: 0,   height: 1.95, content, attachments)

            // Inner ring at eye level: live info flanking the clear center.
            place("detection", angle: -38, height: 1.45, content, attachments)
            place("eventLog",  angle:  38, height: 1.45, content, attachments)

            // Instrument cluster: workflow low center, closer in, below the
            // work zone like a car dashboard — visible but never in the way.
            place("workflow",  angle: 0,   height: 0.95, radius: 1.1, content, attachments)

            // Outer ring: controls further out on each side.
            place("actions",   angle:  62, height: 1.2,  content, attachments)
            
            // Chat on the right outer ring, near actions. Hidden until toggled.
            place("chat", angle: 62, height: 1.55, content, attachments)

            // Sim-only test panels take the outer left.
            #if targetEnvironment(simulator)
            place("upload",    angle: -62, height: 1.4,  content, attachments)
            place("stations",  angle: -62, height: 0.9,  content, attachments)
            #endif
        } update: { _, attachments in
            setEnabled("statusBar", attachments)
            setEnabled("detection", attachments)
            setEnabled("eventLog",  attachments)
            setEnabled("workflow",  attachments)
            setEnabled("chat", attachments)
        } attachments: {
            Attachment(id: "statusBar") { StatusBarPanel() }
            Attachment(id: "detection") { DetectionPanel(service: detectionService) }
            Attachment(id: "eventLog")  { EventLogPanel() }
            Attachment(id: "workflow")  { WorkflowProgressPanel() }
            #if targetEnvironment(simulator)
            Attachment(id: "upload")   { DetectionUploadPanel(service: detectionService) }
            Attachment(id: "stations") { StationPickerPanel(manager: stationManager) }
            #endif
            Attachment(id: "chat") {
                ChatPanel() }
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
                    QuickAction(label: "Reset", icon: "arrow.clockwise", tint: SPAIColor.critical) {
                        appModel.resetWorkflow()
                    }
                ])
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
            Task { await stationManager.startImageTracking() }
            #endif
        }
        // Hardware-only: start the live camera feed and route frames into the
        // existing detection pipeline. Each throttled frame is converted to a
        // UIImage and sent through the SAME detectionService.detect() the
        // upload flow uses — so panels, alerts, and borders all react identically.
        #if !targetEnvironment(simulator)
        .task {
            cameraService.onFrameForDetection = { readOnlyBuffer in
                guard let image = UIImage.from(readOnlyBuffer: readOnlyBuffer) else { return }
                Task { await detectionService.detect(image: image, step: SterileStep(rawValue: appModel.currentStepIndex)) }
            }
            await cameraService.start()
        }
        #endif
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            #if !targetEnvironment(simulator)
            cameraService.stop()
            #endif
        }
    }

    /// Convert (angle, height) on the cockpit arc into a 3D position.
    /// 0° is straight ahead, negative left, positive right. sin gives the
    /// sideways offset, cos gives the forward distance — so every panel
    /// lands exactly `radius` meters away no matter the angle.
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
        panel.components.set(BillboardComponent())
        content.add(panel)
    }

    private func setEnabled(_ id: String, _ attachments: RealityViewAttachments) {
        attachments.entity(for: id)?.isEnabled = appModel.isVisible(id)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
