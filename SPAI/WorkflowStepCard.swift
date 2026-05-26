//
//  WorkflowStepCard.swift
//  SPAI
//

import SwiftUI

struct WorkflowStepCard: View {
    let step: WorkflowStep

    var body: some View {
        HStack(spacing: SPAISpacing.m - 2) {
            Text("\(step.number)")
                .font(.headline)
                .foregroundStyle(step.status == .active ? .white : SPAIColor.neutralDark.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(circleBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(step.status == .locked
                        ? SPAIColor.neutralDark.opacity(0.4)
                        : SPAIColor.neutralDark)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(SPAIColor.neutralDark.opacity(0.55))
            }

            Spacer()
        }
        .padding(SPAISpacing.m)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium)
                .stroke(
                    step.status == .active
                        ? SPAIColor.primary.opacity(0.3)
                        : Color.black.opacity(0.05),
                    lineWidth: 1
                )
        }
    }

    private var circleBackground: Color {
        switch step.status {
        case .active:   return SPAIColor.primary
        case .complete: return SPAIColor.safe
        case .locked:   return SPAIColor.neutralMid.opacity(0.5)
        }
    }

    private var cardBackground: Color {
        switch step.status {
        case .active:   return SPAIColor.primary.opacity(0.08)
        case .complete: return SPAIColor.safe.opacity(0.10)
        case .locked:   return Color.white.opacity(0.5)
        }
    }

    private var statusText: String {
        switch step.status {
        case .active:   return "Active now"
        case .complete: return "Completed"
        case .locked:   return "Locked"
        }
    }
}
