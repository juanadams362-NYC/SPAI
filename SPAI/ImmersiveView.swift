//
//  ImmersiveView.swift
//  SPAI
//
//  The spatial workspace. Panels built once in `make`, billboarded,
//  draggable via ManipulationComponent. `update` only reads state.
//  Floating glove/hand/contamination markers removed — that info now
//  lives in the merged DetectionPanel. Exit moved to the status bar.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            // One-time setup, pulled in tighter around the user.
            place("statusBar", at: [0, 1.95, -1.5],   content, attachments)
            place("detection", at: [-0.85, 1.45, -1.35], content, attachments)
            place("eventLog",  at: [0.85, 1.45, -1.35],  content, attachments)
            place("workflow",  at: [0, 1.0, -1.3],     content, attachments)
            place("actions",   at: [0.85, 1.0, -1.2],  content, attachments)
        } update: { _, attachments in
            // Read-only: react to visibility toggles.
            setEnabled("statusBar", attachments)
            setEnabled("detection", attachments)
            setEnabled("eventLog",  attachments)
            setEnabled("workflow",  attachments)
        } attachments: {
            Attachment(id: "statusBar") { StatusBarPanel() }
            Attachment(id: "detection") { DetectionPanel() }
            Attachment(id: "eventLog")  { EventLogPanel() }
            Attachment(id: "workflow")  { WorkflowProgressPanel() }
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
                    }
                ])
            }
        }
        .onAppear { appModel.immersiveSpaceState = .open }
        .onDisappear { appModel.immersiveSpaceState = .closed }
    }

    /// One-time setup: place a panel, face it at the user, optionally make it grabbable.
    /// `id` is `some Hashable` so it accepts String ids (panels) and UUID ids alike.
    private func place(
        _ id: some Hashable,
        at position: SIMD3<Float>,
        grabbable: Bool = true,
        _ content: RealityViewContent,
        _ attachments: RealityViewAttachments
    ) {
        guard let panel = attachments.entity(for: id) else { return }
        panel.position = position
        panel.components.set(BillboardComponent())

        if grabbable {
            panel.components.set(HoverEffectComponent())
            ManipulationComponent.configureEntity(
                panel,
                collisionShapes: [ .generateBox(width: 0.9, height: 0.5, depth: 0.1) ]
            )
            if var m = panel.components[ManipulationComponent.self] {
                m.releaseBehavior = .stay
                panel.components.set(m)
            }
        }
        content.add(panel)
    }

    /// update-safe: only reads state and toggles visibility.
    private func setEnabled(_ id: String, _ attachments: RealityViewAttachments) {
        attachments.entity(for: id)?.isEnabled = appModel.isVisible(id)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
