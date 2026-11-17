//
//  StatusBarPanel.swift
//  SPAI
//

import SwiftUI
internal import Combine

struct StatusBarPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var sessionSeconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: SPAISpacing.m) {
            identityBlock
            divider
            sessionTimeBlock
            roleBlock
            modeBlock
            Spacer(minLength: SPAISpacing.l)
            controlButtons
        }
        .padding(.horizontal, SPAISpacing.l)
        .padding(.vertical, SPAISpacing.s + 4)
        .frame(width: 860)
        .spaiPanel(PanelID.statusBar, border: appModel.isHalted ? .critical : .normal)
        .onReceive(timer) { _ in sessionSeconds += 1 }
        .onChange(of: appModel.sessionStart) { _, _ in sessionSeconds = 0 }
    }

    private var identityBlock: some View {
        HStack(spacing: SPAISpacing.s + 2) {
            SterileNodeMark(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("SPAI")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(SPAIText.primary)
                // Whose run this is, so a shared headset is never ambiguous.
                Text(appModel.runMode == .practice ? "\(appModel.learnerDisplayName) · practice" : appModel.learnerDisplayName)
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SPAI. Signed in as \(appModel.learnerDisplayName)\(appModel.runMode == .practice ? ", practice run" : "")")
    }

    private var sessionTimeBlock: some View {
        HStack(spacing: 7) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SPAIColor.primaryBright)
            Text(formattedTime)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SPAIText.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: sessionSeconds)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(SPAIColor.surfaceStrong, in: Capsule())
        .overlay { Capsule().strokeBorder(SPAIColor.hairline, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session time \(sessionSeconds / 60) minutes \(sessionSeconds % 60) seconds")
    }

    private var roleBlock: some View {
        Menu {
            ForEach(TechRole.allCases) { role in
                Button {
                    appModel.role = role
                } label: {
                    if appModel.role == role {
                        Label(role.rawValue, systemImage: "checkmark")
                    } else {
                        Text(role.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.accent)
                Text(appModel.role.rawValue)
                    .font(SPAIFont.label)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(SPAIText.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(SPAIColor.surfaceStrong, in: Capsule())
            .overlay { Capsule().strokeBorder(SPAIColor.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .spaiHitTarget(cornerRadius: 20)
        .accessibilityLabel("Role: \(appModel.role.rawValue)")
        .accessibilityHint("Change who is using SPAI")
    }

    /// Where detection is running. Only speaks up when it isn't the normal
    /// case, so a healthy connection is one quiet dot rather than a label.
    private var modeBlock: some View {
        HStack(spacing: 7) {
            LiveDot(color: modeColor, size: 9, animating: detectionService.mode != .offline)
                .id(detectionService.mode)
            if detectionService.mode != .cloud {
                Text(detectionService.mode.rawValue)
                    .font(SPAIFont.caption.weight(.semibold))
                    .foregroundStyle(modeColor)
            }
        }
        .padding(.horizontal, detectionService.mode == .cloud ? 4 : 10)
        .frame(height: 32)
        .background(detectionService.mode == .cloud ? Color.clear : modeColor.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detection running: \(detectionService.mode.rawValue)")
    }

    private var modeColor: Color {
        switch detectionService.mode {
        case .cloud:    return SPAIColor.safe
        case .onDevice: return SPAIColor.warning
        case .offline:  return SPAIColor.critical
        }
    }

    private var controlButtons: some View {
        HStack(spacing: SPAISpacing.s) {
            panelsMenu

            Button {
                if appModel.isSettingsWindowOpen {
                    dismissWindow(id: "settings")
                    appModel.isSettingsWindowOpen = false
                } else {
                    openWindow(id: "settings")
                    appModel.isSettingsWindowOpen = true
                }
            } label: {
                barButtonLabel("Settings", icon: "gearshape.fill", tint: .white)
            }
            .buttonStyle(.plain)
            .spaiHitTarget(cornerRadius: 14)

            // Ending the session is a two-step menu rather than a single
            // tap: the button sits at eye level where a stray glance-and-
            // pinch could otherwise throw away a session in progress.
            Menu {
                Button(role: .destructive) {
                    Task {
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        openWindow(id: "home")
                    }
                } label: {
                    Label("End Session", systemImage: "xmark.circle.fill")
                }
            } label: {
                barButtonLabel("End", icon: "xmark.circle.fill", tint: SPAIColor.critical)
            }
            .buttonStyle(.plain)
            .spaiHitTarget(cornerRadius: 14)
            .accessibilityLabel("End session")
        }
    }

    /// One menu for everything that isn't needed all the time. This replaces
    /// the separate quick-action rail and the always-open reference panels —
    /// the workspace opens with three panels, and the rest are here.
    private var panelsMenu: some View {
        Menu {
            Section("Open a panel") {
                ForEach(PanelID.optional, id: \.self) { id in
                    Button {
                        appModel.toggleVisibility(id)
                    } label: {
                        Label(PanelID.title(id),
                              systemImage: appModel.isVisible(id) ? "checkmark" : PanelID.icon(id))
                    }
                }
            }

            Section("Workspace") {
                Button {
                    appModel.layout = appModel.layout == .focus ? .everything : .focus
                } label: {
                    Label(appModel.layout == .focus ? "Show Everything" : "Back to Focus",
                          systemImage: appModel.layout == .focus ? "rectangle.3.group" : "rectangle.center.inset.filled")
                }
                Button {
                    appModel.requestRecenter()
                } label: {
                    Label("Bring Panels to Me", systemImage: "scope")
                }
                Button {
                    appModel.requestTour()
                } label: {
                    Label("Replay the Tour", systemImage: "figure.walk")
                }
            }

            if appModel.canRunWorkflow {
                Section {
                    Button(role: .destructive) {
                        appModel.resetWorkflow()
                    } label: {
                        Label("Reset Session", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            barButtonLabel("Panels", icon: "square.grid.2x2.fill", tint: SPAIColor.primary)
        }
        .buttonStyle(.plain)
        .spaiHitTarget(cornerRadius: 14)
        .accessibilityHint("Open the event log, history, Ask SPAI, or test media")
    }

    private func barButtonLabel(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(SPAIFont.button)
        .padding(.horizontal, SPAISpacing.m)
        .frame(height: 44)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        }
    }

    private var divider: some View {
        Rectangle().fill(SPAIColor.hairlineStrong).frame(width: 1, height: 30)
    }

    private var formattedTime: String {
        let minutes = sessionSeconds / 60
        let seconds = sessionSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    StatusBarPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .padding(60)
        .background(.black)
}
