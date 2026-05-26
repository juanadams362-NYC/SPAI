//
//  WorkflowView.swift
//  SPAI
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
            LinearGradient(
                colors: [SPAIColor.neutralLight, Color.white, SPAIColor.neutralMid.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: SPAISpacing.l) {
                leftPanel
                LiveFeedMockView()
                rightPanel
            }
            .padding(SPAISpacing.xl)
        }
        .navigationTitle("Sterile Prep Scan")
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("Workflow")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(SPAIColor.neutralDark)

            Text("AI-guided sterile processing checklist")
                .font(.subheadline)
                .foregroundStyle(SPAIColor.neutralDark.opacity(0.6))

            VStack(spacing: SPAISpacing.s) {
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(SPAIColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
                .shadow(color: SPAIColor.primary.opacity(0.3), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 310)
        .padding(SPAISpacing.l)
        .spaiGlass(.light)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("AI Status")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(SPAIColor.neutralDark)

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

            VStack(alignment: .leading, spacing: SPAISpacing.s) {
                Text("Current Recommendation")
                    .font(.headline)
                    .foregroundStyle(SPAIColor.neutralDark)

                Text("Continue PPE check. Confirm gloves, hand hygiene, and tray readiness before moving forward.")
                    .font(.subheadline)
                    .foregroundStyle(SPAIColor.neutralDark.opacity(0.65))
            }
            .padding(SPAISpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SPAIColor.neutralLight.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
        }
        .frame(width: 340)
        .padding(SPAISpacing.l)
        .spaiGlass(.light)
    }
}

#Preview {
    NavigationStack {
        WorkflowView()
    }
}
