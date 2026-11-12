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
        .spaiPanel(PanelID.statusBar)
        .onReceive(timer) { _ in sessionSeconds += 1 }
    }

    private var identityBlock: some View {
        HStack(spacing: SPAISpacing.s + 2) {
            SterileNodeMark(size: 30)
                .frame(width: 40, height: 40)
                .background(SPAIColor.primary.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            Text("SPAI")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SPAI")
    }

    private var sessionTimeBlock: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(SPAIText.tertiary)
            Text(formattedTime)
                .font(SPAIFont.value)
                .foregroundStyle(.white)
        }
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
            .padding(.horizontal, SPAISpacing.s + 4)
            .padding(.vertical, SPAISpacing.s)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }
        .buttonStyle(.plain)
        .spaiHitTarget()
        .accessibilityLabel("Role: \(appModel.role.rawValue)")
        .accessibilityHint("Change who is using SPAI")
    }

    /// Where detection is running. Only speaks up when it isn't the normal
    /// case, so a healthy connection is one quiet dot rather than a label.
    private var modeBlock: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(modeColor)
                .frame(width: 9, height: 9)
            if detectionService.mode != .cloud {
                Text(detectionService.mode.rawValue)
                    .font(SPAIFont.caption.weight(.semibold))
                    .foregroundStyle(modeColor)
            }
        }
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
                barButtonLabel("Settings", icon: "gearshape.fill", tint: SPAIColor.secondary)
            }
            .buttonStyle(.plain)
            .spaiHitTarget()

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
            .spaiHitTarget()
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
                          systemImage: appModel.layout == .focus ? "rectangle.3.group" : "scope")
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
        .spaiHitTarget()
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
        .padding(.vertical, SPAISpacing.s + 2)
        .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 30)
    }

    private var formattedTime: String {
        let minutes = sessionSeconds / 60
        let seconds = sessionSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct SterileNodeMark: View {
    var size: CGFloat = 38

    private var gradient: LinearGradient {
        LinearGradient(colors: [SPAIColor.primary, SPAIColor.secondary, SPAIColor.accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            SPAIHexagon()
                .stroke(gradient, style: StrokeStyle(lineWidth: size * 0.07, lineJoin: .round))
                .frame(width: size * 0.84, height: size * 0.94)

            Path { p in
                p.move(to: CGPoint(x: size/2, y: size*0.32))
                p.addLine(to: CGPoint(x: size/2, y: size*0.68))
                p.move(to: CGPoint(x: size*0.32, y: size/2))
                p.addLine(to: CGPoint(x: size*0.68, y: size/2))
            }
            .stroke(SPAIColor.primary, style: StrokeStyle(lineWidth: size*0.05, lineCap: .round))

            Circle()
                .stroke(SPAIColor.accent, lineWidth: size*0.05)
                .frame(width: size*0.34, height: size*0.34)

            Circle()
                .fill(SPAIColor.accent)
                .frame(width: size*0.13, height: size*0.13)
        }
        .frame(width: size, height: size)
    }
}

struct SPAIHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width/2, ry = rect.height/2
        let pts = [
            CGPoint(x: cx,      y: cy - ry),
            CGPoint(x: cx + rx, y: cy - ry*0.5),
            CGPoint(x: cx + rx, y: cy + ry*0.5),
            CGPoint(x: cx,      y: cy + ry),
            CGPoint(x: cx - rx, y: cy + ry*0.5),
            CGPoint(x: cx - rx, y: cy - ry*0.5)
        ]
        var p = Path()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }
}

#Preview {
    StatusBarPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .padding(60)
        .background(.black)
}
