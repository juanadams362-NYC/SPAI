//
//  GuidedStepPanel.swift
//  SPAI
//

import SwiftUI

struct GuidedStepPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @Environment(ContinuityCameraService.self) private var continuityCamera
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

            if needsDetectionInput { detectionInputCallout }

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
                .spaiHitTarget()
                .disabled(!satisfied)
                .accessibilityLabel(isLast ? "Finish station" : "Next step")
                .accessibilityHint(satisfied ? "Ready" : "Waiting for detection to confirm this step")
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 380)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: appModel.guidedStepIndex)
        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: needsDetectionInput)
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

    // MARK: - "SPAI can't see anything yet"

    /// Whether SPAI has any way of seeing the user's work right now.
    private var hasDetectionInput: Bool {
        continuityCamera.isRunning || detectionService.hasResult
    }

    /// This step is blocked on a detection that can never arrive, because nothing is feeding
    /// the detector.
    ///
    /// Testers started a step and stalled here: the panel said "Waiting for detection…" and
    /// they had no idea that meant *they* had to supply a photo, a video, or a phone camera.
    /// It reads as the app thinking, not as the app waiting on them.
    private var needsDetectionInput: Bool {
        appModel.stepStarted && canVerify && !satisfied && !hasDetectionInput
    }

    private var detectionInputCallout: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(spacing: SPAISpacing.s) {
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SPAIColor.warning)
                Text("SPAI can't see your work yet")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("This step is confirmed by what the camera sees. Give SPAI something to look at — upload a photo or video, or connect your iPhone as a camera.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openWindow(id: "upload")
                appModel.isUploadWindowOpen = true
                appModel.announce("Upload opened", icon: "photo.badge.plus")
            } label: {
                Label("Show SPAI an image or video", systemImage: "photo.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s)
                    .background(SPAIColor.warning.opacity(0.9), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget(pop: 1.10)
            .accessibilityLabel("Show SPAI an image or video")
            .accessibilityHint("Opens the upload window so this step can be verified")
        }
        .padding(SPAISpacing.m)
        .background(SPAIColor.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: SPAIRadius.small)
                .stroke(SPAIColor.warning.opacity(0.45), lineWidth: 1)
        )
        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
        .accessibilityElement(children: .contain)
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
        // Say who is being waited on. "Waiting for detection…" sounds like the app is busy;
        // it actually means the user has not shown it anything yet.
        if !hasDetectionInput { return "Waiting for you to show SPAI something" }
        return "Looking… hold the view steady"
    }
}

#Preview {
    GuidedStepPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .padding(60)
        .background(.black)
}
