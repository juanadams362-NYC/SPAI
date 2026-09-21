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
        VStack(spacing: SPAISpacing.s + 4) {
            ForEach(actions) { action in
                actionButton(action)
            }
            PanelDragHandle(panelID: "actions")
        }
        .padding(SPAISpacing.s + 4)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    private func actionButton(_ action: QuickAction) -> some View {
        // The earlier two-tap design (first tap expands a label to the LEFT of the button,
        // second tap runs the action) moved the button rightward in the HStack whenever the
        // label appeared. visionOS's gaze hover target was still tracking the button's old
        // position, so the second pinch landed in empty space and the action never fired.
        // Since every action here is a non-destructive panel toggle, a single tap is correct.
        Button {
            // Diagnostic: if this line appears when you press a control and nothing
            // happens, input is reaching SwiftUI and the problem is downstream. If it
            // never appears, the press is not landing on the panel at all.
            SPAILog.debug(.ui, "quick action tapped: \(action.label)")
            action.action()
        } label: {
            Image(systemName: action.icon)
                // Icon scaled proportionally to the larger hit target.
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(action.tint)
                // 64 pt = SPAILayout.iconButton. At the actions panel's 1.35 m viewing
                // distance this subtends ≈ 2.7°, comfortably hittable with indirect pinch.
                .frame(width: SPAILayout.iconButton, height: SPAILayout.iconButton)
                .background(action.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: SPAIRadius.medium)
                        .stroke(action.tint.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
//            .spaiHitTarget()
        .accessibilityLabel(action.label)
    }
}

#Preview {
    ActionPanel(actions: [
        QuickAction(label: "Action Panel", icon: "play.fill", tint: SPAIColor.primary, action: {}),
        QuickAction(label: "Compliance", icon: "checkmark.shield.fill", tint: SPAIColor.safe, action: {}),
        QuickAction(label: "Event Log", icon: "waveform.path.ecg", tint: SPAIColor.accent, action: {})
    ])
    .padding(60)
    .background(.black)
}
