//
//  ImmersiveView.swift
//  SPAI
//
//  The spatial workspace. Panels placed once, billboarded, fixed in a
//  grounded arc around the user with the center kept clear. StationManager
//  drives which step the user is on (a + b). Per-station environments (c)
//  are a future sprint.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(DetectionService.self) private var detectionService
    @State private var stationManager = StationManager()

    var body: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            // Grounded arc. Eye level ~1.5m. Center kept clear.
            // Status bar across the top.
            place("statusBar", at: [0, 1.75, -1.4],      content, attachments)
            // Flanking panels at eye level, angled in.
            place("detection", at: [-0.75, 1.45, -1.25], content, attachments)
            place("eventLog",  at: [0.75, 1.45, -1.25],  content, attachments)
            // Workflow just below eye line, centered but low so center stays open.
            place("workflow",  at: [0, 1.15, -1.3],       content, attachments)
            // Quick actions tucked lower-right.
            place("actions",   at: [0.7, 1.05, -1.15],    content, attachments)

            // Sim-only test panels, lower-left so they don't crowd the work area.
            #if targetEnvironment(simulator)
            place("upload",   at: [-0.7, 1.05, -1.15],   content, attachments)
            place("stations", at: [-0.7, 0.7, -1.05],    content, attachments)
            #endif
        } update: { _, attachments in
            setEnabled("statusBar", attachments)
            setEnabled("detection", attachments)
            setEnabled("eventLog",  attachments)
            setEnabled("workflow",  attachments)
        } attachments: {
            Attachment(id: "statusBar") { StatusBarPanel() }
            Attachment(id: "detection") { DetectionPanel(service: detectionService) }
            Attachment(id: "eventLog")  { EventLogPanel() }
            Attachment(id: "workflow")  { WorkflowProgressPanel() }
            #if targetEnvironment(simulator)
            Attachment(id: "upload")   { DetectionUploadPanel(service: detectionService) }
            Attachment(id: "stations") { StationPickerPanel(manager: stationManager) }
            #endif
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
        .onDisappear { appModel.immersiveSpaceState = .closed }
    }

    private func place(
        _ id: some Hashable,
        at position: SIMD3<Float>,
        _ content: RealityViewContent,
        _ attachments: RealityViewAttachments
    ) {
        guard let panel = attachments.entity(for: id) else { return }
        panel.position = position
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
