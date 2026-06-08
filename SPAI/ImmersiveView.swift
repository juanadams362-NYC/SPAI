//
//  ImmersiveView.swift
//  SPAI
//
//  The spatial workspace. Lays out the HUD panels around the user,
//  each billboarding to face them. Action buttons toggle panel
//  visibility so the user can declutter. Includes an exit control.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    let detections: [Detection] = Detection.sampleDetections

    var body: some View {
        RealityView { content, attachments in
            if let env = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(env)
            }

            // Initial placement happens in the update closure below so it
            // can react to visibility changes.
            for detection in detections {
                if let panel = attachments.entity(for: detection.id) {
                    panel.position = detection.position
                    panel.components.set(BillboardComponent())
                    content.add(panel)
                }
            }
        } update: { content, attachments in
            // Re-evaluated when state changes (e.g. a panel toggled).
            // Show or hide each HUD panel based on its visibility flag.
            syncPanel("statusBar",  at: SIMD3<Float>(0, 2.2, -1.6), content, attachments)
            syncPanel("workflow",   at: SIMD3<Float>(0, 1.0, -1.4), content, attachments)
            syncPanel("compliance", at: SIMD3<Float>(-1.1, 1.6, -1.3), content, attachments)
            syncPanel("eventLog",   at: SIMD3<Float>(1.1, 1.6, -1.3), content, attachments)
            syncPanel("actions",    at: SIMD3<Float>(1.5, 1.0, -1.1), content, attachments)
            syncPanel("exit",       at: SIMD3<Float>(0, 0.4, -1.2), content, attachments)
        } attachments: {
            Attachment(id: "statusBar")  { StatusBarPanel() }
            Attachment(id: "workflow")   { WorkflowProgressPanel() }
            Attachment(id: "compliance") { CompliancePanel() }
            Attachment(id: "eventLog")   { EventLogPanel() }
            Attachment(id: "actions") {
                            ActionPanel(actions: [
                                QuickAction(label: "Show All", icon: "rectangle.3.group.fill", tint: SPAIColor.secondary) {
                                    appModel.showAllPanels()
                                },
                                QuickAction(label: "Workflow", icon: "checklist", tint: SPAIColor.primary) {
                                    appModel.toggleVisibility("workflow")
                                },
                                QuickAction(label: "Compliance", icon: "checkmark.shield.fill", tint: SPAIColor.safe) {
                                    appModel.toggleVisibility("compliance")
                                },
                                QuickAction(label: "Event Log", icon: "waveform.path.ecg", tint: SPAIColor.accent) {
                                    appModel.toggleVisibility("eventLog")
                                }
                            ])
                        }
            Attachment(id: "exit") { exitButton }

            ForEach(detections) { detection in
                Attachment(id: detection.id) {
                    DetectionPanel(detection: detection)
                }
            }
        }
        .onAppear { appModel.immersiveSpaceState = .open }
        .onDisappear { appModel.immersiveSpaceState = .closed }
    }

    /// Adds or removes a panel from the scene based on its visibility flag.
    /// The action cluster and exit are always shown so the user can't trap themselves.
    private func syncPanel(
        _ id: String,
        at position: SIMD3<Float>,
        _ content: RealityViewContent,
        _ attachments: RealityViewAttachments
    ) {
        guard let panel = attachments.entity(for: id) else { return }

        // Actions and exit are always visible; everything else respects the flag.
        let alwaysVisible = (id == "actions" || id == "exit")
        let shouldShow = alwaysVisible || appModel.isVisible(id)

        if shouldShow {
            panel.position = position
            panel.components.set(BillboardComponent())
            if panel.parent == nil { content.add(panel) }
        } else {
            if panel.parent != nil { panel.removeFromParent() }
        }
    }

    private var exitButton: some View {
        Button {
            Task {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                Text("Exit Workflow").fontWeight(.semibold)
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(SPAIColor.critical, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

private struct DetectionPanel: View {
    let detection: Detection

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(spacing: 8) {
                Circle()
                    .fill(detection.status.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: detection.status.color, radius: 4)
                Text(detection.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("\(Int(detection.confidence * 100))% confidence")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(SPAISpacing.m)
        .frame(width: 200, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .ledBorder(cornerRadius: SPAIRadius.medium)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
