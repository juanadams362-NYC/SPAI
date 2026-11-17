//
//  GuidedStepPanel.swift
//  SPAI
//

import SwiftUI

struct GuidedStepPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @State private var consecutiveVerifiedSamples = 0
    @State private var voiceConfirm = VoiceInputManager()
    @State private var voiceListenEnabled = false

    private let requiredVerifiedSamples = 3

    private var script: [GuidedStep] { StationScripts.script(for: appModel.currentStep) }

    private var guidedIndex: Int {
        min(appModel.guidedStepIndex, script.count - 1)
    }

    private var step: GuidedStep { script[guidedIndex] }
    private var isLast: Bool { guidedIndex == script.count - 1 }
    private var isManualStep: Bool { step.condition == .manual }

    private var canVerify: Bool {
        step.condition != .manual
    }

    private var satisfied: Bool {
        if step.condition == .manual { return true }
        if !canVerify { return true }
        switch step.condition {
        case .glovesOn:
            return detectionService.detections.contains {
                DetectionService.isGloveClass($0.className)
            }
        case .instrumentsPresent:
            return detectionService.hasInstrumentDetection
        case .trayLoaded:
            return detectionService.trayState == "loaded"
        case .manual:
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            PanelHeader("Guided · \(appModel.currentStep.title)", icon: appModel.currentStep.icon, tint: SPAIColor.primary) {
                Text("Step \(guidedIndex + 1) of \(script.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SPAIColor.primaryBright)
            }

            stepMeter

            Text(step.instruction)
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(SPAIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .id(guidedIndex)
                .transition(AnyTransition.opacity.combined(with: AnyTransition.offset(y: 8)))

            HStack(spacing: SPAISpacing.s) {
                verificationChip

                Spacer(minLength: 8)

                Button {
                    if isLast {
                        appModel.completeStep()
                    } else {
                        appModel.advanceGuidedStep()
                    }
                } label: {
                    Label(isLast ? "Finish Station" : "Next Step",
                          systemImage: isLast ? "checkmark.seal.fill" : "arrow.right")
                }
                .buttonStyle(.spai(.primary))
                .disabled(!satisfied)
                .accessibilityLabel(isLast ? "Finish station" : "Next step")
                .accessibilityHint(satisfied ? "Ready" : "Waiting for detection to confirm this step")
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 400)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(appModel.isHalted ? .critical : .normal, cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.easeInOut(duration: 0.25), value: appModel.guidedStepIndex)
        .onChange(of: detectionService.resultRevision) { _, _ in
            recordVerificationSample()
        }
        // MARK: Voice-confirm (manual steps only)
        // Owns a separate VoiceInputManager; starts when a manual step is active,
        // auto-restarts after recognizer timeout, stops cleanly on advance or disappear.
        // voiceListenEnabled gates the restart watcher so an intentional stop (keyword
        // detected) doesn't immediately re-arm the listener before the step advances.
        .task(id: "\(appModel.currentStepIndex)-\(guidedIndex)") {
            voiceListenEnabled = false
            voiceConfirm.stopListening()
            guard isManualStep, appModel.stepStarted, !appModel.isHalted else { return }
            voiceListenEnabled = true
            voiceConfirm.transcript = ""
            await voiceConfirm.startListening()
        }
        .onChange(of: voiceConfirm.isListening) { _, listening in
            // Auto-restart if the recognizer timed out or errored mid-step.
            guard !listening, voiceListenEnabled,
                  isManualStep, appModel.stepStarted, !appModel.isHalted else { return }
            voiceConfirm.transcript = ""
            Task { await voiceConfirm.startListening() }
        }
        .onChange(of: voiceConfirm.transcript) { _, newTranscript in
            let words = newTranscript.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
            guard isManualStep, voiceListenEnabled,
                  words.contains("done") || words.contains("confirmed") else { return }
            voiceListenEnabled = false   // block isListening restart before step advances
            voiceConfirm.stopListening()
            advanceStep()
        }
        .onChange(of: appModel.guidedStepIndex) { _, _ in
            resetVerificationSamples()
        }
        .onChange(of: appModel.currentStepIndex) { _, _ in
            resetVerificationSamples()
            voiceListenEnabled = false
            voiceConfirm.stopListening()
        }
        .onChange(of: appModel.stepStarted) { _, started in
            resetVerificationSamples()
            if started && isManualStep && !appModel.isHalted {
                voiceListenEnabled = true
                voiceConfirm.transcript = ""
                Task { await voiceConfirm.startListening() }
            } else {
                voiceListenEnabled = false
                voiceConfirm.stopListening()
            }
        }
        .onDisappear {
            voiceListenEnabled = false
            voiceConfirm.stopListening()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guided step \(guidedIndex + 1) of \(script.count), \(appModel.currentStep.title). \(step.instruction) \(verificationText)")
    }

    private func recordVerificationSample() {
        guard appModel.stepStarted,
              !appModel.isHalted,
              step.condition != .manual else {
            resetVerificationSamples()
            return
        }

        if satisfied {
            consecutiveVerifiedSamples += 1
        } else {
            resetVerificationSamples()
        }

        guard consecutiveVerifiedSamples >= requiredVerifiedSamples else { return }
        resetVerificationSamples()
        if isLast {
            appModel.completeStep()
        } else {
            appModel.advanceGuidedStep()
        }
    }

    private func resetVerificationSamples() {
        consecutiveVerifiedSamples = 0
    }

    private func advanceStep() {
        if isLast {
            appModel.completeStep()
        } else {
            appModel.advanceGuidedStep()
        }
    }

    // MARK: - Visual pieces

    /// One segment per instruction in this station's script.
    private var stepMeter: some View {
        HStack(spacing: 5) {
            ForEach(0..<script.count, id: \.self) { index in
                Capsule()
                    .fill(index <= guidedIndex
                          ? AnyShapeStyle(SPAIGradient.brand)
                          : AnyShapeStyle(Color.white.opacity(0.14)))
                    .frame(height: 5)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: guidedIndex)
        .accessibilityHidden(true)
    }

    private var verificationTint: Color {
        if step.condition == .manual { return SPAIColor.accent }
        if satisfied { return SPAIColor.safe }
        return Color.white.opacity(0.72)
    }

    private var verificationChip: some View {
        HStack(spacing: 8) {
            if isManualStep && voiceConfirm.isListening {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .bold))
                    .symbolEffect(.variableColor.iterative)
            } else {
                Image(systemName: verificationIcon)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(verificationText)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if step.condition != .manual {
                HStack(spacing: 3) {
                    ForEach(0..<requiredVerifiedSamples, id: \.self) { index in
                        Capsule()
                            .fill(index < consecutiveVerifiedSamples ? SPAIColor.safe : Color.white.opacity(0.2))
                            .frame(width: 10, height: 5)
                    }
                }
            }
        }
        .foregroundStyle(verificationTint)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(verificationTint.opacity(0.12), in: Capsule())
        .overlay { Capsule().strokeBorder(verificationTint.opacity(0.3), lineWidth: 1) }
        .animation(.easeInOut(duration: 0.2), value: consecutiveVerifiedSamples)
        .animation(.easeInOut(duration: 0.2), value: satisfied)
    }

    private var verificationIcon: String {
        if step.condition == .manual { return "hand.tap.fill" }
        if !canVerify { return "icloud.slash" }
        return satisfied ? "checkmark.circle.fill" : "viewfinder.circle"
    }

    private var verificationText: String {
        if step.condition == .manual { return "Say \"done\" or tap to confirm" }
        if !canVerify { return "Can't verify offline — confirm manually" }
        if satisfied {
            return "Verified \(min(consecutiveVerifiedSamples, requiredVerifiedSamples))/\(requiredVerifiedSamples)"
        }
        return "Waiting for detection…"
    }
}

#Preview {
    GuidedStepPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .padding(60)
        .background(.black)
}
