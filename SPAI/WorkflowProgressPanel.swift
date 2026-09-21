//
//  WorkflowProgressPanel.swift
//  SPAI
//

// All sizing is now proportional to panelWidth. Change panelWidth to update look everywhere.

import SwiftUI

struct WorkflowProgressPanel: View {
    @Environment(AppModel.self) private var appModel
    var panelWidth: CGFloat = 350 // Default for previews and fallback

    private var currentStep: SterileStep { appModel.currentStep }
    private var currentStepIndex: Int { appModel.currentStepIndex }
    private var stepStarted: Bool { appModel.stepStarted }

    private var canSendBack: Bool {
        stepStarted && currentStepIndex > 0
    }

    private var canRedo: Bool {
        appModel.role == .trainee && stepStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: panelWidth * 0.013) {
            header

            HStack(spacing: 0) {
                ForEach(SterileStep.allCases) { step in
                    stepNode(step)
                    if step != SterileStep.allCases.last {
                        connector(after: step)
                    }
                }
            }

            controls
            PanelDragHandle(panelID: "workflow")
        }
        .padding(panelWidth * 0.021)
        .frame(width: panelWidth)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        // Leads with the step and the next action, so VoiceOver answers "what am I doing and
        // what do I do next" in the first breath — the same question the panel now answers
        // visually.
        .accessibilityLabel("Workflow progress. Step \(currentStepIndex + 1) of \(SterileStep.allCases.count), \(currentStep.title). \(nextActionPrompt)")
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: currentStepIndex)
        .animation(.easeInOut(duration: 0.3), value: stepStarted)
    }

    // MARK: - Header

    /// Names the current step and says what to do about it. The tester had to ask the
    /// assistant what she was supposed to be doing, because the panel showed progress nodes
    /// but never stated the step in words or gave the next action.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: panelWidth * 0.013) {
            VStack(alignment: .leading, spacing: panelWidth * 0.006) {
                Text("NOW — \(currentStep.title.uppercased())")
                    .font(.system(size: panelWidth * 0.049, weight: .bold))
                    .foregroundStyle(.white)

                Text(nextActionPrompt)
                    .font(.system(size: panelWidth * 0.038))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // 1-based: this read "0/5" while standing on the first of five steps.
            Text("STEP \(currentStepIndex + 1) OF \(SterileStep.allCases.count)")
                .font(.system(size: panelWidth * 0.034, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize()
        }
    }

    private var nextActionPrompt: String {
        if appModel.sessionComplete {
            return "Session complete — your report is ready."
        }
        if appModel.isHalted {
            return "Contamination detected. Acknowledge below to resume."
        }
        if !appModel.canRunWorkflow {
            return "You're viewing as \(appModel.role.rawValue). Switch to Technician to run a step."
        }
        if stepStarted {
            return "In progress — follow the guided instructions on the right."
        }
        return "Tap Start Step to begin. SPAI will need to see your work through the camera or an uploaded image."
    }

    private var controls: some View {
        HStack(spacing: panelWidth * 0.013) {
            if appModel.isHalted {
                Label("CONTAMINATION — WORKFLOW HALTED", systemImage: "exclamationmark.octagon.fill")
                    .font(.system(size: panelWidth * 0.04, weight: .bold))
                    .foregroundStyle(SPAIColor.critical)

                Spacer()

                if appModel.canRunWorkflow {
                    actionButton("Acknowledge & Resume", icon: "checkmark.shield.fill", tint: SPAIColor.critical) {
                        appModel.acknowledgeContamination()
                    }
                }
            } else if !appModel.canRunWorkflow {
                Label("Viewing as \(appModel.role.rawValue) — read only",
                      systemImage: appModel.role == .observer ? "eye.fill" : "checkmark.seal.fill")
                    .font(.system(size: panelWidth * 0.04, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Text(stepStarted ? "In progress: \(currentStep.title)" : "Ready: \(currentStep.title)")
                    .font(.system(size: panelWidth * 0.037))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text(stepStarted ? "In progress: \(currentStep.title)" : "Ready to start: \(currentStep.title)")
                    .font(.system(size: panelWidth * 0.04))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if !stepStarted {
                    actionButton("Start Step", icon: "play.fill", tint: SPAIColor.primary) {
                        appModel.startStep()
                    }
//                    .tourHighlight(active: appModel.tour.currentStep?.advanceOn == .startedStep)
                } else {
                    if canRedo {
                        actionButton("Redo Step", icon: "arrow.counterclockwise", tint: SPAIColor.secondary) {
                            appModel.redoStep()
                        }
                    }
                    if canSendBack {
                        actionButton("Fail / Send Back", icon: "exclamationmark.triangle.fill", tint: SPAIColor.warning) {
                            appModel.failStep()
                        }
                    }
                    actionButton("Complete Step", icon: "checkmark", tint: SPAIColor.safe) {
                        appModel.completeStep()
                    }
                }
            }
        }
    }

    // MARK: - Step node

    private func stepNode(_ step: SterileStep) -> some View {
        let isCurrent = step.rawValue == currentStepIndex
        let isComplete = step.rawValue < currentStepIndex

        return VStack(spacing: panelWidth * 0.023) {
            ZStack {
                Circle()
                    .fill(nodeFill(isCurrent: isCurrent, isComplete: isComplete))
                    .frame(width: panelWidth * 0.126, height: panelWidth * 0.126)
                    .scaleEffect(isCurrent ? 1.12 : 1.0)
                    .shadow(
                        color: isCurrent ? SPAIColor.primary.opacity(0.6) : .clear,
                        radius: isCurrent ? 8 : 0
                    )

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: panelWidth * 0.045, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else if isCurrent {
                    Image(systemName: stepStarted ? "circle.fill" : "play.fill")
                        .font(.system(size: panelWidth * 0.04, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(step.title)
                .font(.system(size: panelWidth * 0.034, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .white : .white.opacity(0.5))
                .frame(width: panelWidth * 0.257)
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

    private func actionButton(
        _ label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: panelWidth * 0.04, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, panelWidth * 0.043)
                .padding(.vertical, (panelWidth * 0.016) + 2)
                .background(tint, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
        }
        .buttonStyle(.plain)
//        .spaiHitTarget()
    }
}

#Preview {
    WorkflowProgressPanel(panelWidth: 350)
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
