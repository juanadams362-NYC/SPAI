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
    @State private var expandedID: UUID?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(actions) { action in
                actionButton(action)
            }
        }
        .padding(10)
        .spaiPanelBackground(opacity: appModel.panelOpacity, cornerRadius: 36)
        .ledBorder(cornerRadius: 36, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    private func actionButton(_ action: QuickAction) -> some View {
        let isExpanded = expandedID == action.id

        return HStack(spacing: SPAISpacing.s) {
            if isExpanded {
                HStack(spacing: 6) {
                    Text(action.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SPAIColor.textPrimary)
                    Text("· tap again")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SPAIColor.textTertiary)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(action.tint.opacity(0.2), in: Capsule())
                .overlay { Capsule().strokeBorder(action.tint.opacity(0.45), lineWidth: 1) }
                .transition(AnyTransition.move(edge: .trailing).combined(with: AnyTransition.opacity))
                .accessibilityHidden(true)
            }

            Button {
                if isExpanded {
                    action.action()
                    withAnimation(.easeOut(duration: 0.2)) { expandedID = nil }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expandedID = action.id }
                }
            } label: {
                Image(systemName: action.icon)
            }
            .buttonStyle(.spaiIcon(tint: action.tint, size: 52, filled: isExpanded))
            // Icon-only buttons read as nothing to VoiceOver, and this one
            // needs two taps, so say what each tap does.
            .accessibilityLabel(action.label)
            .accessibilityHint(isExpanded ? "Double tap to run" : "Double tap to confirm, then again to run")
        }
    }
}

#Preview {
    ActionPanel(actions: [
        QuickAction(label: "Action Panel", icon: "play.fill", tint: SPAIColor.primary, action: {}),
        QuickAction(label: "Compliance", icon: "checkmark.shield.fill", tint: SPAIColor.safe, action: {}),
        QuickAction(label: "Event Log", icon: "waveform.path.ecg", tint: SPAIColor.accent, action: {})
    ])
    .environment(AppModel())
    .padding(60)
    .background(.black)
}
