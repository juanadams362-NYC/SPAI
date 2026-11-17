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
    @State private var pushSucceeded = false
    @State private var isPushing = false
    private let client = BackendClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            section("Detection", icon: "viewfinder", tint: SPAIColor.secondary) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend URL")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SPAIColor.textSecondary)
                    TextField("http://127.0.0.1:8000", text: $backendURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Backend URL")
                }

                sliderRow("Confidence threshold", value: String(format: "%.2f", confidenceThreshold), tint: SPAIColor.secondary) {
                    Slider(value: $confidenceThreshold, in: 0.05...0.95, step: 0.05)
                        .tint(SPAIColor.secondary)
                        .accessibilityLabel("Confidence threshold")
                }

                sliderRow("Streaming FPS", value: "\(Int(streamingFPS))", tint: SPAIColor.accent) {
                    Slider(value: $streamingFPS, in: 1...30, step: 1)
                        .tint(SPAIColor.accent)
                        .accessibilityLabel("Streaming frames per second")
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await pushThreshold() }
                    } label: {
                        HStack(spacing: 8) {
                            if isPushing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                            Text("Apply to backend")
                        }
                    }
                    .buttonStyle(.spai(.primary))
                    .disabled(isPushing)
                    .accessibilityLabel("Apply confidence threshold to backend")

                    if let pushStatus {
                        SPAIChip(text: pushStatus,
                                 icon: pushSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                 tint: pushSucceeded ? SPAIColor.safe : SPAIColor.warning)
                            .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.9)))
                    }
                }
                .animation(.snappy, value: pushStatus)
            }

            section("Workspace", icon: "rectangle.3.group", tint: SPAIColor.primary) {
                sliderRow("Panel opacity", value: "\(Int(appModel.panelOpacity * 100))%", tint: SPAIColor.primary) {
                    Slider(
                        value: Binding(
                            get: { appModel.panelOpacity },
                            set: { appModel.panelOpacity = $0 }
                        ),
                        in: 0.5...1.0,
                        step: 0.05
                    )
                    .tint(SPAIColor.primary)
                    .accessibilityLabel("Panel opacity")
                }

                toggleRow("Panels look at you", icon: "person.and.arrow.left.and.arrow.right",
                          isOn: Binding(
                            get: { appModel.panelsBillboard },
                            set: { appModel.panelsBillboard = $0 }
                          ))
                    .accessibilityHint("When enabled, panels follow your gaze and rotate to face you")
            }

            section("Guidance & testing", icon: "speaker.wave.2.fill", tint: SPAIColor.accent) {
                // Reads each guided step out loud as it comes up. Contamination
                // alerts speak regardless of this setting.
                toggleRow("Speak step instructions", icon: "speaker.wave.2.fill", isOn: $speakSteps)
                    .accessibilityHint("Reads each guided step aloud when it appears")

                toggleRow("Always show onboarding", icon: "rectangle.stack.fill", isOn: $alwaysShowOnboarding)
            }
        }
        .padding(28)
        .frame(width: 440)
        .spaiWindowBackground(cornerRadius: 36, aurora: false)
        // Closing via the system's own window controls should also clear
        // the tracked-open flag, or the next status bar tap tries to
        // dismiss a window that's already gone.
        .onDisappear {
            appModel.isSettingsWindowOpen = false
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SPAIColor.onFill)
                .frame(width: 44, height: 44)
                .background(SPAIGradient.brand, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: SPAIColor.primaryBright.opacity(0.4), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text("Tune detection and your workspace")
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.textTertiary)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .spaiEyebrow()
            }
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
    }

    private func sliderRow<Control: View>(
        _ title: String,
        value: String,
        tint: Color,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SPAIColor.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
                    .contentTransition(.numericText())
            }
            control()
        }
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SPAIColor.textSecondary)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SPAIColor.textPrimary)
            }
        }
        .tint(SPAIColor.primary)
    }

    private func pushThreshold() async {
        isPushing = true
        defer { isPushing = false }
        do {
            let updated = try await client.updateConfidenceThreshold(confidenceThreshold)
            pushSucceeded = true
            pushStatus = "Backend now at \(String(format: "%.2f", updated.confidenceThreshold))"
        } catch {
            pushSucceeded = false
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
