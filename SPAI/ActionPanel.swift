//
//  ActionPanel.swift
//  SPAI
//

import SwiftUI

struct QuickAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void
}

struct ActionPanel: View {
    let actions: [QuickAction]

    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: SPAISpacing.xs + 2) {
            ForEach(actions) { action in
                actionButton(action)
            }
            PanelDragHandle(panelID: "actions")
        }
        .padding(10)
        // Explicit width is required: PanelDragHandle contains two Spacer() views in an HStack.
        // Without a fixed width here, those Spacers expand to fill whatever RealityKit offers
        // (the full viewport), making the panel enormous. All other panels set frame(width:) for
        // the same reason.
        .frame(width: 180)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    private func actionButton(_ action: QuickAction) -> some View {
        // Labels are always visible — no expand-on-tap mechanic. The old two-tap design
        // inserted the label dynamically to the left of the icon on the first tap, shifting
        // the button rightward. visionOS's gaze anchor still tracked the old position, so
        // the second pinch missed and the action never fired. Static labels have no layout
        // shift and no gesture risk.
        Button {
            SPAILog.debug(.ui, "quick action tapped: \(action.label)")
            action.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(action.tint)
                    .frame(width: 22, alignment: .center)
                Text(action.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // 14pt × 2 + ~16pt line-height ≈ 44pt — at the gaze-pinch floor.
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(action.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.medium)
                    .stroke(action.tint.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
//        .spaiHitTarget()
        .accessibilityLabel(action.label)
    }
}

#Preview {
    ActionPanel(actions: [
        QuickAction(label: "Show All", icon: "rectangle.3.group.fill", tint: SPAIColor.secondary, action: {}),
        QuickAction(label: "Workflow", icon: "checklist", tint: SPAIColor.primary, action: {}),
        QuickAction(label: "Detection", icon: "viewfinder", tint: SPAIColor.accent, action: {}),
        QuickAction(label: "Event Log", icon: "waveform.path.ecg", tint: SPAIColor.primary, action: {}),
        QuickAction(label: "History", icon: "clock.arrow.circlepath", tint: SPAIColor.secondary, action: {}),
        QuickAction(label: "Reset", icon: "arrow.clockwise", tint: SPAIColor.critical, action: {})
    ])
    .environment(AppModel())
    .padding(60)
    .background(.black)
}
