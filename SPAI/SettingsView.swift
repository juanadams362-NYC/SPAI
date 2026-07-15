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

    @State private var pushStatus: String?
    private let client = BackendClient()

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("SETTINGS")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))

            settingBlock(title: "Backend URL") {
                TextField( "http://127.0.0.1:8000", text: $backendURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
            }

            settingBlock(title: "Confidence threshold: \(String(format: "%.2f", confidenceThreshold))") {
                Slider(value: $confidenceThreshold, in: 0.05...0.95, step: 0.05)
                    .tint(SPAIColor.primary)
            }

            settingBlock(title: "Streaming FPS: \(Int(streamingFPS))") {
                Slider(value: $streamingFPS, in: 1...30, step: 1)
                    .tint(SPAIColor.accent)
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
            }

            Toggle(isOn: $alwaysShowOnboarding) {
                Text("Always show onboarding (testing)")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .tint(SPAIColor.primary)

            Button {
                Task { await pushThreshold() }
            } label: {
                Label("Apply to backend", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            if let pushStatus {
                Text(pushStatus)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(SPAISpacing.xl)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
    }

    private func settingBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            content()
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
