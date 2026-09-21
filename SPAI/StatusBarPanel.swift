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

    /// Width driven by SPAILayout.barWidth (1 200 pt = 1.2 m at 1.55 m viewing distance ≈ 44°).
    /// Spacing and padding below are tighter than the other panels so all content fits.
    var panelWidth: CGFloat = SPAILayout.barWidth

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SPAISpacing.m) {
                identityBlock
                divider
                sessionTimeBlock
                divider
                roleBlock
                divider
                modeBlock
                Spacer(minLength: 0)
                controlButtons
            }
            .padding(.horizontal, SPAISpacing.m)
            .padding(.vertical, SPAISpacing.m)
            PanelDragHandle(panelID: "statusBar")
                .padding(.horizontal, SPAISpacing.m)
                .padding(.bottom, SPAISpacing.xs)
        }
        .frame(width: panelWidth)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status bar. Role \(appModel.role.rawValue). Detection \(detectionService.mode.rawValue).")
    }

    private var identityBlock: some View {
        HStack(spacing: SPAISpacing.s + 4) {
            SterileNodeMark(size: 38)
                .frame(width: 48, height: 48)
                .background(SPAIColor.primary.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))

            VStack(alignment: .leading, spacing: 2) {
                Text("SPAI")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("SPD — OR Suite 3")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // Extracted into its own view so the 1-second timer tick only re-renders the
    // clock display. When sessionSeconds lived on StatusBarPanel itself the entire
    // body re-evaluated every second, including controlButtons — and a re-render
    // that overlapped with visionOS's ~150 ms pinch-recognition window could cancel
    // the gesture before the button action fired.
    private var sessionTimeBlock: some View {
        SessionTimeView()
    }

    /// Roles are laid out inline rather than behind a `Menu`. A menu costs two pinches — one
    /// to open it, one to choose — and it hid the feature entirely: the tester never worked
    /// out that roles existed. Every role is now visible and one pinch away.
    private var roleBlock: some View {
        HStack(spacing: 10) {
            Text("ROLE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.trailing, 2)

            ForEach(TechRole.allCases) { role in
                let isOn = appModel.role == role
                Button {
                    appModel.role = role
                } label: {
                    Text(role.rawValue)
                        .font(.system(size: 13, weight: isOn ? .bold : .medium))
                        .foregroundStyle(isOn ? Color.black : .white.opacity(0.85))
                        .padding(.horizontal, SPAISpacing.s + 2)
                        .padding(.vertical, 14)
                        .background(
                            isOn ? AnyShapeStyle(SPAIColor.accent) : AnyShapeStyle(Color.white.opacity(0.10)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
//                .spaiHitTarget(minSize: 40, pop: 1.10)
                .accessibilityLabel("\(role.rawValue) role")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                // Pulse all role pills when the tour step is waiting on a role change.
                .tourHighlight(
                    active: appModel.tour.currentStep?.advanceOn == .changedRole,
                    color: SPAIColor.accent,
                    cornerRadius: SPAIRadius.pill
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: appModel.role)
    }

    private var modeBlock: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(detectionService.mode == .cloud ? SPAIColor.safe :
                      detectionService.mode == .onDevice ? SPAIColor.warning : SPAIColor.critical)
                .frame(width: 8, height: 8)
            Text(detectionService.mode.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, SPAISpacing.s)
        .padding(.vertical, 5)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
    }

    private var controlButtons: some View {
        HStack(spacing: SPAISpacing.m) {
            Button {
                appModel.toggleVisibility("chat")
            } label: {
                barButtonLabel("Ask SPAI", icon: "sparkles", tint: SPAIColor.primary)
            }
            .buttonStyle(.plain)
//            .spaiHitTarget()
            .accessibilityLabel("Ask SPAI")
            .accessibilityValue(appModel.isVisible("chat") ? "Open" : "Closed")
            .accessibilityHint("Opens the assistant, which knows your current step")
            .accessibilityAddTraits(appModel.isVisible("chat") ? [.isSelected] : [])
            // Highlight when wrist menus are off and the tour is waiting on the chat action.
//            .tourHighlight(
//                active: !appModel.wristMenusEnabled
//                    && appModel.tour.currentStep?.advanceOn == .openedChat
//            )

            Button {
                // Same debounced decision the wrist menu uses, so the two cannot disagree
                // about whether Settings is open.
                switch appModel.requestSettingsToggle() {
                case .open:   openWindow(id: "settings")
                case .close:  dismissWindow(id: "settings")
                case .ignore: break
                }
            } label: {
                barButtonLabel("Settings", icon: "gearshape.fill", tint: SPAIColor.secondary)
            }
            .buttonStyle(.plain)
//            .spaiHitTarget()
            .accessibilityLabel("Settings")
            .accessibilityValue(appModel.isSettingsWindowOpen ? "Open" : "Closed")
            .accessibilityAddTraits(appModel.isSettingsWindowOpen ? [.isSelected] : [])
            // Highlight when wrist menus are off and the tour is waiting on settings.
//            .tourHighlight(
//                active: !appModel.wristMenusEnabled
//                    && appModel.tour.currentStep?.advanceOn == .openedSettings,
//                color: SPAIColor.secondary
//            )

            Button {
                Task {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    openWindow(id: "home")
                }
            } label: {
                barButtonLabel("End Session", icon: "xmark.circle.fill", tint: SPAIColor.critical)
            }
            .buttonStyle(.plain)
//            .spaiHitTarget()
            .accessibilityLabel("End session")
            .accessibilityHint("Closes the immersive workspace and returns to the home window")
        }
    }

    private func barButtonLabel(_ text: String, icon: String, tint: Color) -> some View {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(text)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, SPAILayout.buttonVPad)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 36)
    }

}

/// Owns the session timer so only this small view re-renders on each tick.
private struct SessionTimeView: View {
    @State private var seconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Label dropped to save horizontal space in the status bar.
        // The monospaced timer is self-explanatory as the only running counter visible.
        Text(formatted)
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, SPAISpacing.m)
            .padding(.vertical, SPAISpacing.s)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            .onReceive(timer) { _ in seconds += 1 }
    }

    private var formatted: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
