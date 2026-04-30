//
//  WorkflowStepCard.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct WorkflowStepCard: View {
    let step: WorkflowStep

    var body: some View {
        HStack(spacing: 14) {
            Text("\(step.number)")
                .font(.headline)
                .foregroundStyle(step.status == .active ? .black : .white)
                .frame(width: 36, height: 36)
                .background(circleBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(step.status == .active ? 0.24 : 0.08), lineWidth: 1)
        }
    }

    private var circleBackground: Color {
        switch step.status {
        case .active:
            return .white
        case .complete:
            return .green.opacity(0.7)
        case .locked:
            return .white.opacity(0.12)
        }
    }

    private var cardBackground: Color {
        switch step.status {
        case .active:
            return .white.opacity(0.16)
        case .complete:
            return .green.opacity(0.16)
        case .locked:
            return .white.opacity(0.06)
        }
    }

    private var statusText: String {
        switch step.status {
        case .active:
            return "Active now"
        case .complete:
            return "Completed"
        case .locked:
            return "Locked"
        }
    }
}

#Preview {
    WorkflowStepCard(
        step: WorkflowStep(number: 1, title: "PPE Check", status: .active)
    )
    .padding()
    .background(.black)
}
