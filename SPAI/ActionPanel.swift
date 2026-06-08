//
//  QuickAction.swift
//  SPAI
//
//  Created by Juan Adams on 6/7/26.
//


//
//  ActionPanel.swift
//  SPAI
//
//  A compact vertical cluster of quick actions (the floating button
//  stack from the Figma). Each action is an icon button that reveals
//  its label, and triggers a callback so the parent can respond.
//

import SwiftUI

/// One quick action in the cluster.
struct QuickAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void
}

struct ActionPanel: View {
    let actions: [QuickAction]

    // Which action's label is currently expanded (tap to reveal).
    @State private var expandedID: UUID?

    var body: some View {
        VStack(spacing: SPAISpacing.s + 4) {
            ForEach(actions) { action in
                actionButton(action)
            }
        }
        .padding(SPAISpacing.s + 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    private func actionButton(_ action: QuickAction) -> some View {
        let isExpanded = expandedID == action.id

        return HStack(spacing: SPAISpacing.s) {
            // The label slides in when expanded.
            if isExpanded {
                Text(action.label)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                // Tap once to reveal the label; tap again to fire the action.
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
                    .background(action.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: SPAIRadius.medium)
                            .stroke(action.tint.opacity(0.4), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
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