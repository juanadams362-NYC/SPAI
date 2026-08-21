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
        VStack(spacing: SPAISpacing.s + 4) {
            ForEach(actions) { action in
                actionButton(action)
            }
        }
        .padding(SPAISpacing.s + 4)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    private func actionButton(_ action: QuickAction) -> some View {
        let isExpanded = expandedID == action.id

        return HStack(spacing: SPAISpacing.s) {
            if isExpanded {
                Text(action.label)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityHidden(true)
            }

            Button {
                if isExpanded {
                    action.action()
                    withAnimation(.easeOut(duration: 0.2)) { expandedID = nil }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { expandedID = action.id }
                }
            } label: {
                Image(systemName: action.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(action.tint)
                    .frame(width: 52, height: 52)
                    .background(action.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: SPAIRadius.medium)
                            .stroke(action.tint.opacity(0.5), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
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
    .padding(60)
    .background(.black)
}
