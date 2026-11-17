//
//  WorkflowProgressPanel.swift
//  SPAI
//

import SwiftUI

struct WorkflowProgressPanel: View {
    @Environment(AppModel.self) private var appModel

    private var currentStep: SterileStep { appModel.currentStep }
    private var currentStepIndex: Int { appModel.currentStepIndex }
    private var stepStarted: Bool { appModel.stepStarted }

    private var canSendBack: Bool {
        stepStarted && currentStepIndex > 0
    }

    private var canRedo: Bool {
        appModel.role == .trainee && stepStarted
    }

    private var completedCount: Int {
        appModel.sessionComplete ? SterileStep.allCases.count : currentStepIndex
    }

    private let nodeSize: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelHeader("Workflow", icon: "checklist", tint: SPAIColor.primary) {
                Text(appModel.sessionComplete
                     ? "All \(SterileStep.allCases.count) complete"
                     : "Station \(currentStepIndex + 1) of \(SterileStep.allCases.count)")
                    .font(SPAIFont.value)
                    .foregroundStyle(SPAIText.secondary)
                    .contentTransition(.numericText())
            }

            HStack(alignment: .top, spacing: 0) {
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
        .spaiPanel(PanelID.workflow, border: appModel.isHalted ? .critical : .normal)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: currentStepIndex)
        .animation(.easeInOut(duration: 0.3), value: stepStarted)
        .animation(.easeInOut(duration: 0.3), value: appModel.isHalted)
        .animation(.easeInOut(duration: 0.3), value: appModel.sessionComplete)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if appModel.isHalted {
            haltedBanner
        } else if appModel.sessionComplete {
            HStack(spacing: SPAISpacing.m) {
                statusLabel(eyebrow: "Session complete", title: "All stations verified",
                            tint: SPAIColor.safe, icon: "checkmark.seal.fill")
                Spacer()
                Button {
                    appModel.resetWorkflow()
                } label: {
                    Label("New Session", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.spai(.primary))
            }
        } else if !appModel.canRunWorkflow {
            HStack(spacing: SPAISpacing.m) {
                Label("Viewing as \(appModel.role.rawValue) · read only",
                      systemImage: appModel.role == .observer ? "eye.fill" : "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SPAIColor.textSecondary)
                Spacer()
                Text(stepStarted ? "In progress: \(currentStep.title)" : "Ready: \(currentStep.title)")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIColor.textTertiary)
            }
        } else {
            HStack(spacing: 10) {
                statusLabel(eyebrow: stepStarted ? "In progress" : "Next up",
                            title: currentStep.title,
                            tint: stepStarted ? SPAIColor.primaryBright : SPAIColor.textTertiary,
                            icon: currentStep.icon)
                Spacer()

                if !stepStarted {
                    Button {
                        appModel.startStep()
                    } label: {
                        Label("Start Step", systemImage: "play.fill")
                    }
                    .buttonStyle(.spai(.primary))
                } else {
                    if canRedo {
                        Button {
                            appModel.redoStep()
                        } label: {
                            Label("Redo", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.spai(.tinted(SPAIColor.secondary)))
                    }
                    if canSendBack {
                        Button {
                            appModel.failStep()
                        } label: {
                            Label("Fail / Send Back", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.spai(.tinted(SPAIColor.warning)))
                    }
                    Button {
                        appModel.completeStep()
                    } label: {
                        Label("Complete Step", systemImage: "checkmark")
                    }
                    .buttonStyle(.spai(.success))
                }
            }
        }
    }

    private var haltedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SPAIColor.critical)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text("Contamination detected")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text(appModel.canRunWorkflow
                     ? "Workflow halted — re-glove, then acknowledge to resume."
                     : "Workflow halted — waiting for the technician to acknowledge.")
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.textSecondary)
            }

            Spacer()

            if appModel.canRunWorkflow {
                Button {
                    appModel.acknowledgeContamination()
                } label: {
                    Label("Acknowledge & Resume", systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(.spai(.danger))
            }
        }
        .padding(14)
        .background(SPAIColor.critical.opacity(0.14), in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                .strokeBorder(SPAIColor.critical.opacity(0.5), lineWidth: 1)
        }
        .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.97)))
    }

    private func statusLabel(eyebrow: String, title: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow)
                    .spaiEyebrow(tint)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SPAIColor.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Step node

    private func stepNode(_ step: SterileStep) -> some View {
        let isComplete = step.rawValue < currentStepIndex || appModel.sessionComplete
        let isCurrent = step.rawValue == currentStepIndex && !appModel.sessionComplete

        return VStack(spacing: 10) {
            ZStack {
                if isCurrent {
                    Circle()
                        .fill(SPAIColor.primaryBright.opacity(0.18))
                        .frame(width: nodeSize + 16, height: nodeSize + 16)
                    if stepStarted {
                        PulseRing(color: SPAIColor.primaryBright, size: nodeSize)
                    }
                }

                Circle()
                    .fill(nodeFill(isCurrent: isCurrent, isComplete: isComplete))
                    .frame(width: nodeSize, height: nodeSize)
                    .overlay {
                        Circle().strokeBorder(nodeStroke(isCurrent: isCurrent, isComplete: isComplete), lineWidth: 1.5)
                    }
                    .shadow(color: isCurrent ? SPAIColor.primaryBright.opacity(0.6) : (isComplete ? SPAIColor.safe.opacity(0.35) : .clear),
                            radius: isCurrent ? 12 : 6)

                Group {
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(SPAIColor.onFill)
                    } else if isCurrent {
                        Image(systemName: step.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SPAIColor.onFill)
                    } else {
                        Text("\(step.rawValue + 1)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(SPAIColor.textTertiary)
                    }
                }
                .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
            }
            .frame(width: nodeSize + 16, height: nodeSize + 16)

            Text(step.title)
                .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? SPAIColor.textPrimary : (isComplete ? SPAIColor.textSecondary : SPAIColor.textTertiary))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 100)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title), \(isComplete ? "complete" : (isCurrent ? "current" : "upcoming"))")
    }

    private func nodeFill(isCurrent: Bool, isComplete: Bool) -> AnyShapeStyle {
        if isComplete { return AnyShapeStyle(SPAIGradient.success) }
        if isCurrent  { return AnyShapeStyle(SPAIGradient.brand) }
        return AnyShapeStyle(SPAIColor.surface)
    }

    private func nodeStroke(isCurrent: Bool, isComplete: Bool) -> Color {
        if isComplete || isCurrent { return Color.white.opacity(0.45) }
        return SPAIColor.hairlineStrong
    }

    // MARK: - Connector

    private func connector(after step: SterileStep) -> some View {
        let done = step.rawValue < currentStepIndex || appModel.sessionComplete
        let leadsToCurrent = step.rawValue + 1 == currentStepIndex && !appModel.sessionComplete
        return Capsule()
            .fill(connectorFill(done: done, leadsToCurrent: leadsToCurrent))
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -12)
            .padding(.top, (nodeSize + 16) / 2 - 2)
    }

    private func connectorFill(done: Bool, leadsToCurrent: Bool) -> AnyShapeStyle {
        if leadsToCurrent {
            return AnyShapeStyle(LinearGradient(colors: [SPAIColor.safe, SPAIColor.primaryBright],
                                                startPoint: .leading, endPoint: .trailing))
        }
        if done { return AnyShapeStyle(SPAIColor.safe) }
        return AnyShapeStyle(Color.white.opacity(0.12))
    }
}

/// An expanding ring that signals "in progress".
struct PulseRing: View {
    var color: Color
    var size: CGFloat

    @State private var expand = false

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.7), lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(expand ? 1.5 : 1)
            .opacity(expand ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    expand = true
                }
            }
            .allowsHitTesting(false)
    }
}

#Preview {
    WorkflowProgressPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
