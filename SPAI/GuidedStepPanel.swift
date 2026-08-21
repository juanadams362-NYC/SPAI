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
            HStack {
                Text("GUIDED · \(appModel.currentStep.title.uppercased())")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("Step \(guidedIndex + 1) of \(script.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SPAIColor.accent)
            }

            Text(step.instruction)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SPAISpacing.s) {
                Image(systemName: verificationIcon)
                    .foregroundStyle(satisfied ? SPAIColor.safe : SPAIColor.warning)
                Text(verificationText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Button {
                    if isLast {
                        appModel.completeStep()
                    } else {
                        appModel.advanceGuidedStep()
                    }
                } label: {
                    Label(isLast ? "Finish Station" : "Next Step",
                          systemImage: isLast ? "checkmark.seal" : "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, SPAISpacing.m)
                        .padding(.vertical, SPAISpacing.s)
                        .background(satisfied ? SPAIColor.primary : SPAIColor.neutralMid.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
                .disabled(!satisfied)
                .accessibilityLabel(isLast ? "Finish station" : "Next step")
                .accessibilityHint(satisfied ? "Ready" : "Waiting for detection to confirm this step")
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 380)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
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
