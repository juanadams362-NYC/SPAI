//
//  GuidedStepPanel.swift
//  SPAI
//

import SwiftUI

/// The instruction for the step in hand, and the check that lets it advance.
///
/// Three rules shape this panel:
///
/// 1. **One instruction at a time**, large enough to read at a glance.
/// 2. **Never a dead end.** A camera-checked step that the camera can't
///    confirm offers "Confirm by hand" after a short wait. A student must
///    never be stuck in front of a greyed-out button because of lighting or
///    a camera that isn't connected. The override is recorded.
/// 3. **Hands stay on the work.** Every step answers to voice: "next",
///    "repeat", "why", "what is this".
struct GuidedStepPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @AppStorage("voiceCommands") private var voiceCommands = true

    @State private var consecutiveVerifiedSamples = 0
    @State private var voice = VoiceInputManager()
    @State private var voiceListenEnabled = false
    /// When the current step began waiting on the camera.
    @State private var waitingSince = Date()
    @State private var canOverride = false

    private let requiredVerifiedSamples = 3
    /// How long a camera check may stall before the hand-confirm appears.
    private let overrideAfter: TimeInterval = 12

    private var script: [GuidedStep] { StationScripts.script(for: appModel.currentStep) }
    private var guidedIndex: Int { min(appModel.guidedStepIndex, script.count - 1) }
    private var step: GuidedStep { script[guidedIndex] }
    private var isLast: Bool { guidedIndex == script.count - 1 }
    private var isManualStep: Bool { step.condition == .manual }
    private var isActive: Bool { appModel.stepStarted && !appModel.isHalted }

    private var countCheck: CountSheetCheck {
        CountSheetCheck.check(sheet: ProtocolStore.shared.countSheet, seen: detectionService.instrumentCounts)
    }

    private var satisfied: Bool {
        switch step.condition {
        case .manual:
            return true
        case .glovesOn:
            // Gloves seen and no bare hand: one gloved hand doesn't pass the
            // step while the other is bare.
            return detectionService.ppePassing
        case .instrumentsPresent:
            return detectionService.hasInstrumentDetection
        case .trayLoaded:
            return detectionService.trayState == "loaded" || detectionService.hasInstrumentDetection
        case .countMatches:
            return countCheck.matches
        }
    }

    /// The step can move on: the check passed, or it has been waived.
    private var canAdvance: Bool { satisfied || canOverride }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header

            Text(step.instruction)
                .font(SPAIFont.instruction)
                .lineSpacing(3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Trainees are learning why as well as what.
            if appModel.role == .trainee, !step.why.isEmpty {
                Label(step.why, systemImage: "lightbulb.fill")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step.condition == .countMatches {
                countSheet
            }

            footer

            if voiceCommands {
                HStack(spacing: 8) {
                    if voice.isListening {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative)
                            .foregroundStyle(SPAIColor.secondary)
                    } else {
                        Image(systemName: "mic.slash")
                            .foregroundStyle(SPAIText.tertiary)
                    }
                    Text(voice.isListening ? "Say \"next\", \"repeat\", \"why\", or \"what is this\""
                                           : "Voice commands paused")
                        .foregroundStyle(SPAIText.tertiary)
                }
                .font(SPAIFont.caption)
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 460)
        .spaiPanel(PanelID.guided, border: appModel.isHalted ? .critical : .normal)
        .animation(.easeInOut(duration: 0.25), value: appModel.guidedStepIndex)
        .animation(.easeInOut(duration: 0.25), value: canOverride)
        .onChange(of: detectionService.resultRevision) { _, _ in
            recordVerificationSample()
        }
        // One task per step: resets the stall timer, restarts listening, and
        // arms the hand-confirm if the camera hasn't verified in time.
        .task(id: "\(appModel.currentStepIndex)-\(guidedIndex)-\(appModel.stepStarted)-\(appModel.isHalted)") {
            consecutiveVerifiedSamples = 0
            canOverride = false
            waitingSince = Date()
            await restartListening()
            guard isActive, !isManualStep else { return }
            try? await Task.sleep(for: .seconds(overrideAfter))
            guard !Task.isCancelled, isActive, !satisfied else { return }
            canOverride = true
        }
        .onChange(of: voice.isListening) { _, listening in
            // The recognizer times out after a while; pick it back up.
            guard !listening, voiceListenEnabled, isActive else { return }
            Task { await voice.startListening() }
        }
        .onChange(of: voice.transcript) { _, transcript in
            handleSpeech(transcript)
        }
        .onChange(of: voiceCommands) { _, _ in
            Task { await restartListening() }
        }
        .onDisappear {
            voiceListenEnabled = false
            voice.stopListening()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guided step \(guidedIndex + 1) of \(script.count), \(appModel.currentStep.title). \(step.instruction) \(verificationText)")
    }

    // MARK: - Pieces

    private var header: some View {
        PanelHeader(appModel.currentStep.title, icon: appModel.currentStep.icon, tint: SPAIColor.primary) {
            // Dots show how far through the station you are without
            // making you read a fraction.
            HStack(spacing: 6) {
                ForEach(0..<script.count, id: \.self) { index in
                    Capsule()
                        .fill(index < guidedIndex ? AnyShapeStyle(SPAIColor.safe)
                              : index == guidedIndex ? AnyShapeStyle(SPAIGradient.brand)
                              : AnyShapeStyle(Color.white.opacity(0.25)))
                        .frame(width: index == guidedIndex ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: guidedIndex)
            .accessibilityHidden(true)
            Text("\(guidedIndex + 1) of \(script.count)")
                .font(SPAIFont.value)
                .foregroundStyle(SPAIColor.primaryBright)
        }
    }

    /// The tray's expected contents, ticked off as the camera recognises them.
    private var countSheet: some View {
        let check = countCheck
        return VStack(alignment: .leading, spacing: 6) {
            Text(ProtocolStore.shared.countSheet.name)
                .spaiEyebrow()

            ForEach(check.rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.isMatched ? "checkmark.circle.fill"
                                      : row.isMissing ? "circle" : "exclamationmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(row.isMatched ? SPAIColor.safe
                                         : row.isMissing ? SPAIText.tertiary : SPAIColor.warning)
                    Text(row.name)
                        .font(SPAIFont.label)
                        .foregroundStyle(row.isMatched ? .white : SPAIText.secondary)
                    Spacer()
                    Text("\(row.seen) of \(row.expected)")
                        .font(SPAIFont.value)
                        .foregroundStyle(row.isMatched ? SPAIColor.safe : SPAIText.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name): \(row.seen) of \(row.expected)\(row.isMatched ? ", matched" : "")")
            }

            if !check.unexpected.isEmpty {
                Label("Not on the sheet: \(check.unexpected.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SPAISpacing.s + 4)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: SPAISpacing.s) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(verificationText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: verificationIcon)
                }
                .font(SPAIFont.label)
                .foregroundStyle(verificationTint)

                // Three frames in a row must agree before a camera check passes.
                if !isManualStep && !canOverride {
                    HStack(spacing: 4) {
                        ForEach(0..<requiredVerifiedSamples, id: \.self) { index in
                            Capsule()
                                .fill(index < consecutiveVerifiedSamples || satisfied
                                      ? SPAIColor.safe : Color.white.opacity(0.2))
                                .frame(width: 14, height: 5)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: consecutiveVerifiedSamples)
                    .accessibilityHidden(true)
                }
            }

            Spacer(minLength: SPAISpacing.s)

            Button {
                advance()
            } label: {
                Label(advanceLabel, systemImage: isLast ? "checkmark.seal.fill" : (canOverride && !satisfied ? "hand.tap.fill" : "arrow.right"))
            }
            .buttonStyle(.spai(!satisfied && canOverride ? .tinted(SPAIColor.warning) : .primary))
            .disabled(!canAdvance)
            .accessibilityLabel(advanceLabel)
            .accessibilityHint(satisfied ? "Ready" : canOverride ? "The camera couldn't confirm this step" : "Waiting for the camera to confirm this step")
        }
    }

    private var advanceLabel: String {
        if !satisfied && canOverride { return "Confirm by hand" }
        return isLast ? "Finish Station" : "Next Step"
    }

    // MARK: - Advancing

    /// The camera has to agree several frames in a row before a step
    /// advances on its own, so one lucky frame can't skip a check.
    private func recordVerificationSample() {
        guard isActive, !isManualStep else {
            consecutiveVerifiedSamples = 0
            return
        }
        consecutiveVerifiedSamples = satisfied ? consecutiveVerifiedSamples + 1 : 0
        guard consecutiveVerifiedSamples >= requiredVerifiedSamples else { return }
        consecutiveVerifiedSamples = 0
        moveOn()
    }

    /// The user pressed the button or said "next".
    private func advance() {
        guard isActive, canAdvance else { return }
        if !satisfied {
            // Waived, not passed. Say so in the record, and for a count
            // sheet, say exactly what didn't match.
            if step.condition == .countMatches {
                appModel.recordCountMismatch(countCheck.summary)
            } else {
                appModel.recordManualOverride(waitingText)
            }
        }
        moveOn()
    }

    private func moveOn() {
        voiceListenEnabled = false
        voice.stopListening()
        if isLast {
            appModel.completeStep()
        } else {
            appModel.advanceGuidedStep()
        }
    }

    // MARK: - Voice

    private func restartListening() async {
        voiceListenEnabled = false
        voice.stopListening()
        guard voiceCommands, isActive else { return }
        voice.transcript = ""
        voiceListenEnabled = true
        await voice.startListening()
    }

    private func handleSpeech(_ transcript: String) {
        guard voiceListenEnabled, isActive, !transcript.isEmpty else { return }
        // SPAI's own voice comes back through the microphone. Ignore
        // anything heard while it is talking, or it would obey itself.
        guard !SpeechManager.shared.isSpeaking else {
            voice.transcript = ""
            return
        }

        let heard = transcript.lowercased()
        let words = Set(heard.components(separatedBy: CharacterSet.alphanumerics.inverted))

        if !words.isDisjoint(with: ["next", "done", "confirmed", "confirm", "finished"]) {
            if canAdvance {
                advance()
            } else {
                SpeechManager.shared.speak("Not yet. \(waitingText)", force: true)
                resetHearing()
            }
        } else if !words.isDisjoint(with: ["repeat", "again"]) {
            appModel.repeatGuidedStep()
            resetHearing()
        } else if words.contains("why") {
            SpeechManager.shared.speak(step.why.isEmpty ? "There's no note for this step." : step.why, force: true)
            resetHearing()
        } else if heard.contains("what is this") || heard.contains("what's this") || heard.contains("what am i holding") {
            SpeechManager.shared.speak(
                detectionService.identifiedInstrument?.spoken ?? "I can't see an instrument. Hold it up flat, in view of the camera.",
                force: true
            )
            resetHearing()
        }
    }

    /// Clears what was heard so one phrase isn't acted on twice, and lets
    /// the listener restart cleanly.
    private func resetHearing() {
        voice.transcript = ""
        voice.stopListening()
    }

    // MARK: - Status line

    /// Says what SPAI is looking for, so a stalled step explains itself.
    private var waitingText: String {
        switch step.condition {
        case .glovesOn:           return "Looking for your gloves"
        case .instrumentsPresent: return "Looking for instruments"
        case .trayLoaded:         return "Looking for a loaded tray"
        case .countMatches:       return countCheck.summary
        case .manual:             return ""
        }
    }

    private var verificationTint: Color {
        if isManualStep { return SPAIColor.accent }
        if satisfied { return SPAIColor.safe }
        return canOverride ? SPAIColor.warning : SPAIText.secondary
    }

    private var verificationIcon: String {
        if isManualStep { return "hand.tap.fill" }
        if satisfied { return "checkmark.circle.fill" }
        return canOverride ? "exclamationmark.circle" : "viewfinder.circle"
    }

    private var verificationText: String {
        if isManualStep { return "Say \"next\" or tap Next" }
        if satisfied {
            return step.condition == .countMatches ? "Count matches the sheet" : "Confirmed by camera"
        }
        if canOverride {
            return step.condition == .countMatches
                ? "\(countCheck.summary). Fix it, or confirm by hand."
                : "\(waitingText). Can't see it? Confirm by hand."
        }
        return "\(waitingText)…"
    }
}

#Preview {
    GuidedStepPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .padding(60)
        .background(.black)
}
