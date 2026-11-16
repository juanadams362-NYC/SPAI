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
                .accessibilityHint("Takes effect next time the workspace opens.")
            Text("Needs Apple's enterprise main-camera entitlement and license file in this build. Otherwise use an iPhone camera or test media.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
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
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SPAIColor.critical)
                        .padding(.horizontal, SPAISpacing.l)
                        .padding(.vertical, SPAISpacing.s + 2)
                        .overlay { RoundedRectangle(cornerRadius: SPAIRadius.small).stroke(SPAIColor.critical.opacity(0.6)) }
                }
                .buttonStyle(.plain)
                .spaiHitTarget()
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

#Preview {
    SettingsView()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
