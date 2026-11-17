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

    private var borderState: BorderState { appModel.isHalted ? .critical : .normal }

    var body: some View {
        HStack(spacing: 10) {
            identityBlock
            SPAIDivider(vertical: true)
            sessionTimeChip
            if appModel.isHalted {
                haltedChip
                    .transition(AnyTransition.scale(scale: 0.8).combined(with: AnyTransition.opacity))
            } else {
                stationChip
                    .transition(AnyTransition.opacity)
            }
            roleMenu
            modeChip
            Spacer(minLength: SPAISpacing.s)
            controlButtons
        }
        .padding(.horizontal, SPAISpacing.l)
        .padding(.vertical, 14)
        .frame(width: 1200)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(borderState, cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appModel.isHalted)
        .onReceive(timer) { _ in sessionSeconds += 1 }
        .onChange(of: appModel.sessionStart) { _, _ in sessionSeconds = 0 }
    }

    // MARK: - Blocks

    private var identityBlock: some View {
        HStack(spacing: 12) {
            SterileNodeMark(size: 44)

            VStack(alignment: .leading, spacing: 1) {
                Text("SPAI")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text("SPD · OR Suite 3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SPAIColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sessionTimeChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SPAIColor.primaryBright)
            Text(formattedTime)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SPAIColor.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy, value: sessionSeconds)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(SPAIColor.surfaceStrong, in: Capsule())
        .overlay { Capsule().strokeBorder(SPAIColor.hairline, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session time \(formattedTime)")
    }

    private var stationChip: some View {
        let step = appModel.currentStep
        let total = SterileStep.allCases.count
        return HStack(spacing: 8) {
            Image(systemName: step.icon)
                .font(.system(size: 13, weight: .semibold))
            Text("\(step.rawValue + 1)/\(total) · \(step.title)")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(SPAIColor.primaryBright)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(SPAIColor.primary.opacity(0.14), in: Capsule())
        .overlay { Capsule().strokeBorder(SPAIColor.primary.opacity(0.3), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Station \(step.rawValue + 1) of \(total), \(step.title)")
    }

    private var haltedChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .bold))
                .symbolEffect(.pulse)
            Text("Workflow halted")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(SPAIColor.critical)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(SPAIColor.critical.opacity(0.18), in: Capsule())
        .overlay { Capsule().strokeBorder(SPAIColor.critical.opacity(0.55), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var roleMenu: some View {
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
                Image(systemName: roleIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SPAIColor.accent)
                Text(appModel.role.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(SPAIColor.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SPAIColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(SPAIColor.surfaceStrong, in: Capsule())
            .overlay { Capsule().strokeBorder(SPAIColor.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .spaiHitTarget(cornerRadius: 22)
        .accessibilityLabel("Role: \(appModel.role.rawValue)")
        .accessibilityHint("Changes what you can do in this session")
    }

    private var roleIcon: String {
        switch appModel.role {
        case .technician: return "person.fill"
        case .supervisor: return "checkmark.shield.fill"
        case .trainee:    return "graduationcap.fill"
        case .observer:   return "eye.fill"
        }
    }

    private var modeChip: some View {
        let tint: Color
        let label: String
        switch detectionService.mode {
        case .cloud:
            tint = SPAIColor.safe
            label = "Cloud AI"
        case .onDevice:
            tint = SPAIColor.warning
            label = "On-Device"
        case .offline:
            tint = SPAIColor.critical
            label = "Offline"
        }
        return HStack(spacing: 8) {
            LiveDot(color: tint, size: 8, animating: detectionService.mode != .offline)
                .id(detectionService.mode)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detection mode: \(label)")
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button {
                appModel.toggleVisibility("chat")
            } label: {
                Label("Ask SPAI", systemImage: "sparkles")
            }
            .buttonStyle(.spai(.tinted(SPAIColor.secondary)))

            Button {
                if appModel.isSettingsWindowOpen {
                    dismissWindow(id: "settings")
                    appModel.isSettingsWindowOpen = false
                } else {
                    openWindow(id: "settings")
                    appModel.isSettingsWindowOpen = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.spaiIcon(tint: .white, size: 46))
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                Task {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    openWindow(id: "home")
                }
            } label: {
                Label("End Session", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.spai(.tinted(SPAIColor.critical)))
        }
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
