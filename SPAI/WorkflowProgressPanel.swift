//
//  WorkflowProgresssPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/7/26.
//


//
//  WorkflowProgressPanel.swift
//  SPAI
//
//  The horizontal 5-step sterile-processing tracker. Real workflow
//  controls: start, complete, fail/send-back, and (for trainees) redo.
//  Fail sends the tray back to Decontamination — the core SPD rule that
//  any contamination event means full reprocessing.
//

import SwiftUI

/// The five sterile-processing steps, in order.
enum SterileStep: Int, CaseIterable, Identifiable {
    case decontamination
    case inspection
    case trayAssembly
    case packaging
    case sealValidation

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .decontamination: return "Decontamination"
        case .inspection:      return "Inspection"
        case .trayAssembly:    return "Tray Assembly"
        case .packaging:       return "Packaging"
        case .sealValidation:  return "Seal Validation"
        }
    }
}

struct WorkflowProgressPanel: View {
    @Environment(AppModel.self) private var appModel

    // Index of the current step the user is on.
    @State private var currentStepIndex: Int = 0
    // Whether the current step has been started (vs. just selected).
    @State private var stepStarted = false

    private var currentStep: SterileStep {
        SterileStep.allCases[currentStepIndex]
    }

    // A failed step can only be sent back if we're past Decontamination.
    private var canSendBack: Bool {
        stepStarted && currentStepIndex > 0
    }

    // Trainees get a Redo affordance to repeat the current step.
    private var canRedo: Bool {
        appModel.role == .trainee && stepStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header

            // The horizontal step track.
            HStack(spacing: 0) {
                ForEach(SterileStep.allCases) { step in
                    stepNode(step)
                    if step != SterileStep.allCases.last {
                        connector(after: step)
                    }
                }
            }

            controls
        }
        .padding(SPAISpacing.l)
        .frame(width: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("WORKFLOW PROGRESS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text("\(currentStepIndex)/\(SterileStep.allCases.count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Step node

    private func stepNode(_ step: SterileStep) -> some View {
        let isCurrent = step.rawValue == currentStepIndex
        let isComplete = step.rawValue < currentStepIndex

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(nodeFill(isCurrent: isCurrent, isComplete: isComplete))
                    .frame(width: 44, height: 44)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                } else if isCurrent {
                    Image(systemName: stepStarted ? "circle.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            Text(step.title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.5))
                .frame(width: 90)
                .multilineTextAlignment(.center)
        }
    }

    private func nodeFill(isCurrent: Bool, isComplete: Bool) -> Color {
        if isComplete { return SPAIColor.safe }
        if isCurrent  { return SPAIColor.primary }
        return SPAIColor.neutralMid.opacity(0.3)
    }

    // MARK: - Connector

    private func connector(after step: SterileStep) -> some View {
        Rectangle()
            .fill(step.rawValue < currentStepIndex ? SPAIColor.safe : .white.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: SPAISpacing.m) {
            Text(stepStarted ? "In progress: \(currentStep.title)" : "Ready to start: \(currentStep.title)")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if !stepStarted {
                actionButton("Start Step", icon: "play.fill", tint: SPAIColor.primary) {
                    stepStarted = true
                }
            } else {
                // Redo (trainees only) — repeat the current step from scratch.
                if canRedo {
                    actionButton("Redo Step", icon: "arrow.counterclockwise", tint: SPAIColor.secondary) {
                        stepStarted = false
                    }
                }

                // Fail / Send Back — contamination means the tray reprocesses from Decontamination.
                if canSendBack {
                    actionButton("Fail / Send Back", icon: "exclamationmark.triangle.fill", tint: SPAIColor.warning) {
                        currentStepIndex = 0
                        stepStarted = false
                    }
                }

                // Complete — advance to the next step.
                actionButton("Complete Step", icon: "checkmark", tint: SPAIColor.safe) {
                    if currentStepIndex < SterileStep.allCases.count - 1 {
                        currentStepIndex += 1
                        stepStarted = false
                    }
                }
            }
        }
    }

    /// A consistent pill button used across the controls row.
    private func actionButton(
        _ label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, SPAISpacing.l)
                .padding(.vertical, SPAISpacing.s + 2)
                .background(tint, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WorkflowProgressPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
