//
//  WorkflowView.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct WorkflowView: View {
    private let steps = [
        WorkflowStep(number: 1, title: "PPE Check", status: .active),
        WorkflowStep(number: 2, title: "Hand Hygiene", status: .locked),
        WorkflowStep(number: 3, title: "Tool Verification", status: .locked),
        WorkflowStep(number: 4, title: "Tray Inspection", status: .locked),
        WorkflowStep(number: 5, title: "Final Readiness", status: .locked)
    ]

    var body: some View {
        ZStack {
            AppBackground()

            HStack(spacing: 24) {
                leftPanel

                LiveFeedMockView()

                rightPanel
            }
            .padding(32)
        }
        .navigationTitle("Sterile Prep Scan")
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Workflow")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("AI-guided sterile processing checklist")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            VStack(spacing: 12) {
                ForEach(steps) { step in
                    WorkflowStepCard(step: step)
                }
            }

            Spacer()

            Button {
                print("Mark step complete tapped")
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark Step Complete")
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 310)
        .padding(22)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AI Status")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            DetectionAlertCard(
                title: "Glove Detection",
                message: "Gloves detected. PPE check is currently passing.",
                status: .safe,
                confidence: 0.94
            )

            DetectionAlertCard(
                title: "Hand Position",
                message: "Hands visible in scan area. Continue monitoring.",
                status: .review,
                confidence: 0.81
            )

            DetectionAlertCard(
                title: "Contamination Risk",
                message: "No visible contamination risk detected in this frame.",
                status: .clear,
                confidence: 0.88
            )

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("Current Recommendation")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Continue PPE check. Confirm gloves, hand hygiene, and tray readiness before moving forward.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding()
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .frame(width: 340)
        .padding(22)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack {
        WorkflowView()
    }
}
