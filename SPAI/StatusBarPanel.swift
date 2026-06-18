//
//  StatusBarPanel.swift
//  SPAI
//
//  Top HUD status bar: Sterile Node logo, identity, session time, role,
//  and the session actions — Ask SPAI, Settings, End Session.
//

import SwiftUI
internal import Combine

struct StatusBarPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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
            Spacer()
            controlButtons
        }
        .padding(.horizontal, SPAISpacing.l)
        .padding(.vertical, SPAISpacing.m)
        .frame(width: 900)
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
            HStack(spacing: 8) {
                Circle().fill(SPAIColor.accent).frame(width: 8, height: 8)
                Text(appModel.role.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
    }

    private var controlButtons: some View {
        HStack(spacing: SPAISpacing.s + 4) {
            Button {
                // TODO: invoke SPAI assistant (dynamic-island presence)
            } label: {
                barButtonLabel("Ask SPAI", icon: "sparkles", tint: SPAIColor.primary)
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "settings")
            } label: {
                barButtonLabel("Settings", icon: "gearshape.fill", tint: SPAIColor.secondary)
            }
            .buttonStyle(.plain)

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
        }
    }

    private func barButtonLabel(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).foregroundStyle(.white)
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

// MARK: - Sterile Node logo mark

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
        .padding(60)
        .background(.black)
}
