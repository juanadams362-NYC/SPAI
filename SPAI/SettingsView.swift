//
//  SettingsView.swift
//  SPAI
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    @AppStorage("backendURL") private var backendURL =  "http://127.0.0.1:8000"
    @AppStorage("streamingFPS") private var streamingFPS = 5.0
    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false
    @AppStorage("speakSteps") private var speakSteps = false
    @AppStorage("detectOnDevice") private var detectOnDevice = true
    @AppStorage("useHeadsetCamera") private var useHeadsetCamera = false
    @AppStorage("voiceCommands") private var voiceCommands = true
    @State private var connectionStatus: String?
    @State private var school = SchoolConnection.shared
    @State private var confirmDisconnect = false

    private let client = BackendClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                workspaceSection.settingsCard()
                guidanceSection.settingsCard()
                detectionSection.settingsCard()
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
        .frame(width: 440)
        .frame(maxHeight: 760)
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
                    .foregroundStyle(SPAIText.primary)
                Text("Workspace, guidance, privacy and your school")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.tertiary)
            }
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
                    .foregroundStyle(SPAIText.secondary)
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
            }
            .buttonStyle(.spai(.tinted(SPAIColor.primary)))
            .disabled(appModel.immersiveSpaceState != .open || !appModel.showCompanion)
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
                .foregroundStyle(SPAIText.secondary)
                .fixedSize(horizontal: false, vertical: true)

            settingToggle("Use the headset's camera", isOn: $useHeadsetCamera, tint: SPAIColor.safe)
                .accessibilityHint("Takes effect next time the workspace opens.")
            Text("Needs Apple's enterprise main-camera entitlement and license file in this build. Otherwise use an iPhone camera or test media.")
                .font(.system(size: 13))
                .foregroundStyle(SPAIText.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sectionDivider
            sectionTitle("Before a session")
            SystemCheckView()

            sectionDivider
            sectionTitle("School")

            if school.isPaired {
                VStack(alignment: .leading, spacing: 4) {
                    Text(school.schoolName ?? "Connected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("This headset: \(school.headsetName ?? "Headset") · \(backendURL)")
                        .font(SPAIFont.mono)
                        .foregroundStyle(SPAIText.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await testConnection() }
                } label: {
                    Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.spai(.tinted(SPAIColor.accent)))

                // Two presses: disconnecting means an admin has to pair the
                // headset again before students can sign in.
                Button {
                    if confirmDisconnect {
                        Task { await disconnect() }
                    } else {
                        confirmDisconnect = true
                    }
                } label: {
                    Label(confirmDisconnect ? "Press again to disconnect" : "Disconnect this headset",
                          systemImage: "link.badge.plus")
                }
                .buttonStyle(.spai(confirmDisconnect ? .danger : .tinted(SPAIColor.critical)))
            } else {
                Text("Not connected. Connect from the home screen with a code from your school's instructor dashboard.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let connectionStatus {
                Text(connectionStatus)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            sectionDivider
            sectionTitle("Detection")

            settingBlock(title: "Streaming FPS: \(Int(streamingFPS))") {
                Slider(value: $streamingFPS, in: 1...30, step: 1)
                    .tint(SPAIColor.accent)
                    .accessibilityLabel("Streaming frames per second")
            }

        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .spaiEyebrow(SPAIColor.primaryBright)
    }

    private var sectionDivider: some View {
        SPAIDivider()
            .padding(.vertical, 2)
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(SPAIText.primary)
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
                .foregroundStyle(SPAIText.primary)
            content()
        }
    }

    private func testConnection() async {
        connectionStatus = "Checking…"
        switch await client.connection() {
        case .connected:   connectionStatus = "Connected to \(school.schoolName ?? "your school")."
        case .unpaired:    connectionStatus = "This headset was disconnected from the dashboard. Connect it again from the home screen."
        case .unreachable: connectionStatus = "The server didn't answer. Check this headset is online."
        case .outdated:    connectionStatus = "The server is an older version without schools and sign-in."
        }
    }

    private func disconnect() async {
        await client.unpair()
        SchoolConnection.shared.forget()
        RosterCache.clear()
        confirmDisconnect = false
        connectionStatus = "Disconnected."
    }
}

private extension View {
    /// One group of settings on a quiet card.
    func settingsCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                    .strokeBorder(SPAIColor.hairline, lineWidth: 1)
            }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
