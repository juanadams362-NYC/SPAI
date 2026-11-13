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
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("detectOnDevice") private var detectOnDevice = true
    @AppStorage("useHeadsetCamera") private var useHeadsetCamera = true
    @AppStorage("voiceCommands") private var voiceCommands = true
    @State private var connectionStatus: String?

    @State private var pushStatus: String?
    private let client = BackendClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SPAISpacing.l) {
                Text("SETTINGS")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.8))

                workspaceSection
                sectionDivider
                guidanceSection
                sectionDivider
                detectionSection
            }
            .padding(SPAISpacing.xl)
        }
        .frame(width: 420)
        .frame(maxHeight: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        // Closing via the system's own window controls should also clear
        // the tracked-open flag, or the next status bar tap tries to
        // dismiss a window that's already gone.
        .onDisappear {
            appModel.isSettingsWindowOpen = false
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            sectionTitle("Workspace")

            settingBlock(title: "Layout") {
                Picker("Layout", selection: Binding(
                    get: { appModel.layout },
                    set: { appModel.layout = $0 }
                )) {
                    ForEach(PanelLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Workspace layout")

                Text(appModel.layout == .focus
                     ? "Shows only what the current task needs. Open anything else from Panels."
                     : "Opens the event log and test media alongside the essentials.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
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

            settingToggle("Panels turn to face you", isOn: Binding(
                get: { appModel.panelsBillboard },
                set: { appModel.panelsBillboard = $0 }
            ), tint: SPAIColor.accent)
            .accessibilityHint("When on, panels rotate to face you as you move")
        }
    }

    // MARK: - Guidance

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            sectionTitle("Guidance")

            settingToggle("Show Pip, the guide", isOn: Binding(
                get: { appModel.showCompanion },
                set: { appModel.showCompanion = $0 }
            ), tint: SPAIColor.accent)
            .accessibilityHint("Pip hops to the panel that needs your attention")

            settingToggle("Say instrument names aloud", isOn: Binding(
                get: { appModel.announceInstruments },
                set: { appModel.announceInstruments = $0 }
            ), tint: SPAIColor.accent)
            .accessibilityHint("Hold up an instrument and SPAI tells you what it is")

            // Reads each guided step out loud as it comes up. Contamination
            // alerts speak regardless of this setting.
            settingToggle("Speak step instructions", isOn: $speakSteps, tint: SPAIColor.primary)
                .accessibilityHint("Reads each guided step aloud when it appears")

            settingToggle("Voice commands", isOn: $voiceCommands, tint: SPAIColor.primary)
                .accessibilityHint("Say next, repeat, why, or what is this during a step")

            Button {
                appModel.requestTour()
            } label: {
                Label("Replay the tour", systemImage: "figure.walk")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .disabled(appModel.immersiveSpaceState != .open || !appModel.showCompanion)
            .opacity(appModel.immersiveSpaceState == .open && appModel.showCompanion ? 1 : 0.45)
            .accessibilityHint("Pip walks you around the workspace again")

            settingToggle("Always show onboarding (testing)", isOn: $alwaysShowOnboarding, tint: SPAIColor.primary)
        }
    }

    // MARK: - Detection

    private var detectionSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            sectionTitle("Privacy")

            settingToggle("Keep camera frames on this headset", isOn: $detectOnDevice, tint: SPAIColor.safe)
            Text(detectOnDevice
                 ? "Checks run on the headset. Video is never sent to the server; only the record of each run is."
                 : "Frames are sent to your SPAI server for checking and discarded there. They are never stored.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            settingToggle("Use the headset's camera", isOn: $useHeadsetCamera, tint: SPAIColor.safe)
                .accessibilityHint("Needs Apple's main camera access for enterprise. Takes effect next time the workspace opens.")

            sectionDivider
            sectionTitle("Server")

            settingBlock(title: "Server address") {
                TextField( "http://127.0.0.1:8000", text: $backendURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Server address")
            }

            settingBlock(title: "Site key") {
                SecureField("From your SPAI administrator", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Site key")
            }

            Button {
                Task { await testConnection() }
            } label: {
                Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()

            if let connectionStatus {
                Text(connectionStatus)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            sectionDivider
            sectionTitle("Detection")

            settingBlock(title: "Confidence threshold: \(String(format: "%.2f", confidenceThreshold))") {
                Slider(value: $confidenceThreshold, in: 0.05...0.95, step: 0.05)
                    .tint(SPAIColor.primary)
                    .accessibilityLabel("Confidence threshold")
            }

            settingBlock(title: "Streaming FPS: \(Int(streamingFPS))") {
                Slider(value: $streamingFPS, in: 1...30, step: 1)
                    .tint(SPAIColor.accent)
                    .accessibilityLabel("Streaming frames per second")
            }

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
    }

    // MARK: - Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.white)
    }

    private var sectionDivider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.95))
        }
        .tint(tint)
    }

    private func settingBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
            content()
        }
    }

    private func testConnection() async {
        connectionStatus = "Checking…"
        switch await client.connection() {
        case .connected:   connectionStatus = "Connected. This headset is accepted by the server."
        case .unreachable: connectionStatus = "Nothing answered at that address. Check it, and that the headset is on the same network."
        case .wrongKey:    connectionStatus = "The server answered but didn't accept the site key."
        case .outdated:    connectionStatus = "Connected, but the server is an older version without class records."
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
