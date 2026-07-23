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
    @State private var draft = ""
    @State private var isWaiting = false

    var body: some View {
        VStack(spacing: SPAISpacing.m) {
            header
            messageList
            inputBar
        }
        .padding(SPAISpacing.l)
        .frame(width: 340, height: 440)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ask SPAI chat. \(messages.count) messages. Answers are grounded in \(currentStep?.title ?? "no step").")
    }

    private var header: some View {
        HStack {
            Text("ASK SPAI")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(currentStep?.title ?? "No step")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SPAIColor.accent)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: SPAISpacing.s) {
                    ForEach(messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    if isWaiting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("thinking…")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                        }
                        .accessibilityLabel("Waiting for an answer")
                    }
                }
            }
            .onChange(of: messages) { _, newValue in
                if let last = newValue.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 15))
                .padding(.horizontal, SPAISpacing.m)
                .padding(.vertical, SPAISpacing.s)
                .background(bubbleColor(message.role), in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
                .foregroundStyle(.white)
            if message.role != .user { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(speakerName(message.role)): \(message.text)")
    }

    private func speakerName(_ role: ChatMessage.Role) -> String {
        switch role {
        case .user:  return "You said"
        case .spai:  return "SPAI said"
        case .error: return "Error"
        }
    }

    private func bubbleColor(_ role: ChatMessage.Role) -> Color {
        switch role {
        case .user:  return SPAIColor.primary.opacity(0.6)
        case .spai:  return .white.opacity(0.18)
        case .error: return SPAIColor.critical.opacity(0.45)
        }
    }

    private var inputBar: some View {
        HStack(spacing: SPAISpacing.s) {
            TextField("Ask about this step…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .accessibilityLabel("Question field")
                .accessibilityHint("Dictate or type a question about the current step")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isWaiting)
            .accessibilityLabel("Send question")
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
        var parts: [String] = []
        let names = detectionService.detections.map { $0.className.lowercased() }
        parts.append(names.contains("glove") ? "gloves detected" : "no gloves detected")
        if names.contains("hand") { parts.append("bare hand visible") }
        let instrumentHits = names.filter { $0 == "instrument" }.count
        if instrumentHits > 0 {
            parts.append("\(instrumentHits) instruments detected")
        }
        if let tray = detectionService.trayState {
            parts.append("tray is \(tray)")
        }
        return parts.joined(separator: ", ")
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !isWaiting else { return }
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
