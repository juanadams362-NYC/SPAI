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
        HStack(spacing: SPAISpacing.l) {
            identityBlock
            divider
            sessionTimeBlock
            divider
            roleBlock
            divider
            modeBlock
            Spacer(minLength: SPAISpacing.xl)
            controlButtons
        }
        .padding(.horizontal, SPAISpacing.l)
        .padding(.vertical, SPAISpacing.m)
        // Wider than before: the four inline role pills need the room the role menu didn't.
        .frame(width: 1440)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .onReceive(timer) { _ in sessionSeconds += 1 }
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

    private var sessionTimeBlock: some View {
        HStack(spacing: 8) {
            Text("SESSION TIME")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Text(formattedTime)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, SPAISpacing.m)
        .padding(.vertical, SPAISpacing.s)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
    }

    /// Roles are laid out inline rather than behind a `Menu`. A menu costs two pinches — one
    /// to open it, one to choose — and it hid the feature entirely: the tester never worked
    /// out that roles existed. Every role is now visible and one pinch away.
    private var roleBlock: some View {
        HStack(spacing: 4) {
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
                        .padding(.vertical, 6)
                        .background(
                            isOn ? AnyShapeStyle(SPAIColor.accent) : AnyShapeStyle(Color.white.opacity(0.10)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .spaiHitTarget(minSize: 40, pop: 1.10)
                .accessibilityLabel("\(role.rawValue) role")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .animation(.easeOut(duration: 0.18), value: appModel.role)
    }

    private var modeBlock: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(detectionService.mode == .cloud ? SPAIColor.safe :
                      detectionService.mode == .onDevice ? SPAIColor.warning : SPAIColor.critical)
                .frame(width: 8, height: 8)
            Text(detectionService.mode.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, SPAISpacing.m)
        .padding(.vertical, SPAISpacing.s)
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
            .spaiHitTarget()

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
            .spaiHitTarget()
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
            .padding(.horizontal, SPAISpacing.m)
            .padding(.vertical, SPAISpacing.s + 2)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 36)
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
