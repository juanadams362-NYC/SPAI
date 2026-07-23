//
//  ImmersiveView.swift
//  SPAI
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(DetectionService.self) private var detectionService
    @State private var stationManager = StationManager()

    @State private var cameraService = CameraFrameService()

    private let arcRadius: Float = 1.25

    var body: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            place("statusBar", angle: 0, height: 1.9, radius: 1.3, content, attachments)

            place("detection", angle: -30, height: 1.45, radius: 1.2, content, attachments)
            place("eventLog",  angle:  30, height: 1.45, radius: 1.2, content, attachments)

            place("guided",    angle:  16, height: 1.15, radius: 1.15, content, attachments)

            place("workflow",  angle:  0,  height: 0.85, radius: 1.1, content, attachments)

            place("actions",   angle:  52, height: 1.25, radius: 1.3, content, attachments)
            place("chat",      angle:  48, height: 1.7,  radius: 1.3, content, attachments)
            place("history",   angle: -52, height: 1.55, radius: 1.3, content, attachments)

            place("report",    angle:  0,  height: 1.4,  radius: 1.05, content, attachments)

            #if targetEnvironment(simulator)
            place("upload",    angle: -52, height: 1.0,  radius: 1.3, content, attachments)
            place("stations",  angle: -30, height: 0.85, radius: 1.2, content, attachments)
            #endif
        } update: { _, attachments in
            setEnabled("statusBar", attachments)
            setEnabled("detection", attachments)
            setEnabled("eventLog",  attachments)
            setEnabled("workflow",  attachments)
            setEnabled("chat", attachments)
            setEnabled("history", attachments)
            attachments.entity(for: "report")?.isEnabled = appModel.sessionComplete
            attachments.entity(for: "guided")?.isEnabled = appModel.stepStarted && !appModel.sessionComplete && appModel.canRunWorkflow
        } attachments: {
            Attachment(id: "statusBar") { StatusBarPanel() }
            Attachment(id: "detection") { DetectionPanel(service: detectionService) }
            Attachment(id: "eventLog")  { EventLogPanel() }
            Attachment(id: "workflow")  { WorkflowProgressPanel() }
            #if targetEnvironment(simulator)
            Attachment(id: "upload")   { DetectionUploadPanel(service: detectionService) }
            Attachment(id: "stations") { StationPickerPanel(manager: stationManager) }
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
