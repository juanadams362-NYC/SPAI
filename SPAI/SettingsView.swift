//
//  SettingsView.swift
//  SPAI
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @AppStorage("backendURL") private var backendURL =  "http://127.0.0.1:8000"
    @AppStorage("confidenceThreshold") private var confidenceThreshold = 0.25
    @AppStorage("streamingFPS") private var streamingFPS = 5.0
    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false
    @AppStorage("speakSteps") private var speakSteps = false

    @State private var pushStatus: String?
    private let client = BackendClient()

    var body: some View {
        // Scrolls: the explanations and the replay-tour button push this past the window's
        // 700pt height, and a settings row you cannot reach is a settings row that does not exist.
        ScrollView {
            settingsContent
        }
        .scrollIndicators(.visible)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        // Closing via the system's own window controls should also clear
        // the tracked-open flag, or the next status bar tap tries to
        // dismiss a window that's already gone.
        .onDisappear {
            appModel.isSettingsWindowOpen = false
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("SETTINGS")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.8))

            settingBlock(title: "Backend URL") {
                TextField( "http://127.0.0.1:8000", text: $backendURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .accessibilityLabel("Backend URL")
            }

            settingBlock(
                title: "Confidence threshold: \(String(format: "%.0f", confidenceThreshold * 100))%",
                // The tester asked outright what "confidence" meant. Say it in the panel.
                explanation: "How sure SPAI must be before it reports something. Raise it for fewer false alarms, lower it to catch more."
            ) {
                Slider(value: $confidenceThreshold, in: 0.05...0.95, step: 0.05)
                    .tint(SPAIColor.primary)
                    .accessibilityLabel("Confidence threshold")
            }

            settingBlock(
                title: "Streaming FPS: \(Int(streamingFPS))",
                explanation: "Frames per second sent for live detection. Higher is more responsive but works the device harder."
            ) {
                Slider(value: $streamingFPS, in: 1...30, step: 1)
                    .tint(SPAIColor.accent)
                    .accessibilityLabel("Streaming frames per second")
            }

            settingBlock(title: "Panel opacity: \(Int(appModel.panelOpacity * 100))%") {
                Slider(
                    value: Binding(
                        get: { appModel.panelOpacity },
                        set: { appModel.panelOpacity = $0 }
                    ),
                    in: 0.5...1.0,
                    step: 0.05
                )
                .tint(SPAIColor.secondary)
                .accessibilityLabel("Panel opacity")
            }

            Toggle(isOn: Binding(
                get: { appModel.panelsBillboard },
                set: { appModel.panelsBillboard = $0 }
            )) {
                Text("Panels look at you")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .tint(SPAIColor.accent)
            .accessibilityHint("When enabled, panels follow your gaze and rotate to face you")

            // Reads each guided step out loud as it comes up. Contamination
            // alerts speak regardless of this setting.
            Toggle(isOn: $speakSteps) {
                Text("Speak step instructions")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .tint(SPAIColor.primary)
            .accessibilityHint("Reads each guided step aloud when it appears")

            VStack(alignment: .leading, spacing: SPAISpacing.s) {
                Toggle(isOn: $alwaysShowOnboarding) {
                    Text("Always show welcome screens")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .tint(SPAIColor.primary)

                Text("Shows the welcome pages on every launch instead of only the first. Useful while testing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The tour is the thing that actually teaches the workspace, so it needs to be
            // replayable — the tester had no route back to it once it was dismissed.
            Button {
                appModel.restartTour()
            } label: {
                Label("Replay guided tour", systemImage: "play.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.secondary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityHint("Restarts the in-app walkthrough of the workspace")

            Button {
                Task { await pushThreshold() }
            } label: {
                Label("Apply to backend", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityLabel("Apply confidence threshold to backend")

            if let pushStatus {
                Text(pushStatus)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(SPAISpacing.xl)
    }

    private func settingBlock<Content: View>(
        title: String,
        explanation: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
            content()
            if let explanation {
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pushThreshold() async {
        do {
            let updated = try await client.updateConfidenceThreshold(confidenceThreshold)
            pushStatus = "Backend now at \(String(format: "%.2f", updated.confidenceThreshold))"
        } catch {
            pushStatus = "Failed to reach backend"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
