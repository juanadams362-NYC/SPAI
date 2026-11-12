import SwiftUI

#if os(visionOS)
/// Quick actions on the right wrist.
///
/// Turn the back of your right wrist toward you, like checking a watch, and
/// this rises above it. Where it sits and when it shows are owned by
/// `HandTrackingService`; this view is only what's drawn.
///
/// Every button carries a text label. The first version was four unlabelled
/// 14pt glyphs, which nobody could decode at a glance — and a wrist menu is
/// only ever looked at in glances.
struct WristMenuPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// Fixed size in points, so the hand tracker knows exactly how much room
    /// to leave between the menu and the arm.
    static let size = CGSize(width: 212, height: 176)

    private let columns = [GridItem(.fixed(88), spacing: SPAISpacing.s),
                           GridItem(.fixed(88), spacing: SPAISpacing.s)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: SPAISpacing.s) {
            quickButton("Ask SPAI", icon: "sparkles", tint: SPAIColor.accent,
                        isOn: appModel.isVisible(PanelID.chat)) {
                appModel.toggleVisibility(PanelID.chat)
            }
            quickButton("History", icon: "clock.arrow.circlepath", tint: SPAIColor.secondary,
                        isOn: appModel.isVisible(PanelID.history)) {
                appModel.toggleVisibility(PanelID.history)
            }
            quickButton("Event Log", icon: "waveform.path.ecg", tint: SPAIColor.primary,
                        isOn: appModel.isVisible(PanelID.eventLog)) {
                appModel.toggleVisibility(PanelID.eventLog)
            }
            quickButton("Settings", icon: "gearshape.fill", tint: .white,
                        isOn: appModel.isSettingsWindowOpen) {
                if appModel.isSettingsWindowOpen {
                    dismissWindow(id: "settings")
                    appModel.isSettingsWindowOpen = false
                } else {
                    openWindow(id: "settings")
                    appModel.isSettingsWindowOpen = true
                }
            }
        }
        .padding(SPAISpacing.s + 4)
        .frame(width: Self.size.width, height: Self.size.height)
        .spaiWristBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wrist quick actions")
    }

    private func quickButton(
        _ label: String,
        icon: String,
        tint: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 88, height: 72)
            .background(tint.opacity(isOn ? 0.38 : 0.16), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.small)
                    .stroke(tint.opacity(isOn ? 0.95 : 0.4), lineWidth: isOn ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: SPAIRadius.small))
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Preview
#Preview("Wrist Menu Panel") {
    WristMenuPanel()
        .environment(AppModel())
        .padding(40)
        .background(.black)
}
#endif

extension View {
    /// Background for the wrist menus.
    ///
    /// Deliberately near-opaque and ignores the panel-opacity setting: these
    /// are read against a moving background of skin, sleeve, and bench, where
    /// a translucent panel washes out.
    func spaiWristBackground() -> some View {
        self
            .background(Color(white: 0.07).opacity(0.94),
                        in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
            }
    }
}
