//
//  ChatPanel.swift
//  SPAI
//

import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, spai, error }
    let id = UUID()
    let role: Role
    let text: String
}

struct ChatPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService

    private let client = BackendClient()

    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .spai, text: "Ask me anything about your current step.")
    ]
    @State private var voiceInput = VoiceInputManager()
    @State private var draft = ""
    @State private var isWaiting = false

    /// One-tap questions — typing in the headset is slow, so the common asks are a tap away.
    private let suggestions = [
        "What PPE do I need here?",
        "What's my next step?",
        "What mistakes should I avoid?"
    ]

    private var showsSuggestions: Bool {
        !isWaiting && !messages.contains { $0.role == .user }
    }

    var body: some View {
        VStack(spacing: SPAISpacing.m) {
            header
            messageList
            inputBar
        }
        .padding(SPAISpacing.l)
        .frame(width: 360, height: 480)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ask SPAI chat. \(messages.count) messages. Answers are grounded in \(currentStep?.title ?? "no step").")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SPAIColor.onFill)
                .frame(width: 32, height: 32)
                .background(SPAIGradient.ai, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: SPAIColor.secondary.opacity(0.5), radius: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("Ask SPAI")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text("AI guidance for this station")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SPAIColor.textTertiary)
            }
            Spacer(minLength: 6)
            SPAIChip(text: currentStep?.title ?? "No step", icon: currentStep?.icon, tint: SPAIColor.primaryBright)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(messages) { message in
                        bubble(for: message)
                            .id(message.id)
                            .transition(AnyTransition.opacity.combined(with: AnyTransition.offset(y: 10)))
                    }
                    if showsSuggestions {
                        suggestionList
                            .transition(AnyTransition.opacity)
                    }
                    if isWaiting {
                        HStack(spacing: 10) {
                            spaiAvatar
                            TypingDots()
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(SPAIColor.surfaceStrong, in: Capsule())
                            Spacer()
                        }
                        .accessibilityElement()
                        .accessibilityLabel("Waiting for an answer")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .animation(.snappy(duration: 0.3), value: messages)
            .animation(.snappy(duration: 0.3), value: isWaiting)
            .onChange(of: messages) { _, newValue in
                if let last = newValue.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var spaiAvatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(SPAIColor.onFill)
            .frame(width: 26, height: 26)
            .background(SPAIGradient.ai, in: Circle())
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SPAIColor.onFill)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SPAIGradient.brand,
                                in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                           bottomTrailingRadius: 6, topTrailingRadius: 18,
                                                           style: .continuous))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(speakerName(message.role)): \(message.text)")
        case .spai, .error:
            HStack(alignment: .bottom, spacing: 10) {
                if message.role == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SPAIColor.critical)
                        .frame(width: 26, height: 26)
                        .background(SPAIColor.critical.opacity(0.18), in: Circle())
                } else {
                    spaiAvatar
                }
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(SPAIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .error ? SPAIColor.critical.opacity(0.16) : SPAIColor.surfaceStrong,
                        in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                                   bottomTrailingRadius: 18, topTrailingRadius: 18,
                                                   style: .continuous)
                    )
                    .overlay {
                        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                               bottomTrailingRadius: 18, topTrailingRadius: 18,
                                               style: .continuous)
                            .strokeBorder(message.role == .error ? SPAIColor.critical.opacity(0.4) : SPAIColor.hairline,
                                          lineWidth: 1)
                    }
                Spacer(minLength: 28)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(speakerName(message.role)): \(message.text)")
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .spaiEyebrow()
                .padding(.leading, 36)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    ask(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SPAIColor.secondary)
                        Text(suggestion)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SPAIColor.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(SPAIColor.secondary.opacity(0.14), in: Capsule())
                    .overlay { Capsule().strokeBorder(SPAIColor.secondary.opacity(0.35), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .spaiHitTarget(cornerRadius: 19)
                .padding(.leading, 36)
                .accessibilityHint("Asks SPAI this question")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speakerName(_ role: ChatMessage.Role) -> String {
        switch role {
        case .user:  return "You said"
        case .spai:  return "SPAI said"
        case .error: return "Error"
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.xs) {
            HStack(spacing: SPAISpacing.s) {
                TextField("Ask about this step…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(SPAIColor.surfaceStrong, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(voiceInput.isListening ? SPAIColor.secondary.opacity(0.7) : SPAIColor.hairlineStrong,
                                               lineWidth: 1)
                    }
                    .onSubmit(send)
                    .accessibilityLabel("Question field")
                    .accessibilityHint("Dictate or type a question about the current step")

                Button {
                    voiceInput.toggleListening()
                } label: {
                    Image(systemName: voiceInput.isListening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.spaiIcon(tint: voiceInput.isListening ? SPAIColor.warning : SPAIColor.accent, size: 44))
                .disabled(isWaiting)
                .accessibilityLabel(voiceInput.isListening ? "Stop voice input" : "Start voice input")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.spaiIcon(tint: SPAIColor.secondary, size: 44, filled: true))
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isWaiting)
                .accessibilityLabel("Send question")
            }

            if voiceInput.isListening {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                    Text("Listening…")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SPAIColor.secondary)
                .padding(.leading, 8)
            } else if let error = voiceInput.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(SPAIColor.warning)
                    .padding(.leading, 8)
            }
        }
        .onChange(of: voiceInput.transcript) { _, transcript in
            draft = transcript
        }
    }

    // MARK: - Send

    private var currentStep: SterileStep? {
        SterileStep(rawValue: appModel.currentStepIndex)
    }

    // Must match the backend script keys exactly or /ask returns 400.
    private var stationKey: String {
        currentStep?.backendName ?? "decontamination"
    }

    private var detectionSummary: String {
        guard detectionService.hasResult else { return "" }
        let detections = detectionService.detections
        var parts: [String] = []
        let gloves = detections.contains { DetectionService.isGloveClass($0.className) }
        let hands = detections.contains { DetectionService.isHandClass($0.className) }
        parts.append(gloves ? "gloves detected" : "no gloves detected")
        if hands { parts.append("bare hand visible") }
        // On-device instrument labels are specific names ("Scalpel Handle 3"), so match by
        // category rather than the literal string "instrument" the backend uses.
        let instrumentHits = detections.filter { DetectionService.isInstrumentClass($0.className) }.count
        if instrumentHits > 0 {
            parts.append("\(instrumentHits) instruments detected")
        }
        if let tray = detectionService.trayState {
            parts.append("tray is \(tray)")
        }
        return parts.joined(separator: ", ")
    }

    private func ask(_ question: String) {
        draft = question
        send()
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !isWaiting else { return }
        voiceInput.stopListening()
        draft = ""
        messages.append(ChatMessage(role: .user, text: question))
        isWaiting = true

        Task {
            do {
                let response = try await client.ask(AskRequest(
                    question: question,
                    station: stationKey,
                    stepIndex: appModel.guidedStepIndex,
                    detectionSummary: detectionSummary
                ))
                messages.append(ChatMessage(role: .spai, text: response.answer))
            } catch {
                messages.append(ChatMessage(role: .error, text: "Couldn't reach SPAI. Check the backend connection and try again."))
            }
            isWaiting = false
        }
    }
}

#Preview {
    ChatPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .padding(60)
        .background(.black)
}
