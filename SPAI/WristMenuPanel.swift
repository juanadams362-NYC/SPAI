import SwiftUI
import simd

#if os(visionOS)
/// A floating quick-action menu that follows the user's wrist on device, with a simulator fallback.
/// World placement (tracking the live wrist pose vs. a fixed fallback position) is owned by
/// ImmersiveView, which repositions this attachment's RealityKit entity every frame — this view
/// only decides whether it should be visible right now.
struct WristMenuPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// Whether the wrist this panel rides on is currently tracked. Passed as a plain value,
    /// not a closure: the previous version called the closure from `body` and wrote to
    /// `@State` as a side effect, which SwiftUI does not re-evaluate on its own — so once the
    /// arm left the frame nothing invalidated the view and the panel stayed frozen on screen.
    let isHandVisible: Bool

    var body: some View {
        panelContent
            .opacity(shouldShowPanel ? 1 : 0)
            .scaleEffect(shouldShowPanel ? 1 : 0.9)
            .animation(.easeInOut(duration: 0.22), value: shouldShowPanel)
            .allowsHitTesting(shouldShowPanel)
    }

    // MARK: - Derived State

    private var shouldShowPanel: Bool {
        #if targetEnvironment(simulator)
        // Hand tracking never runs in the simulator, so pin the panel visible there.
        return true
        #else
        return isHandVisible
        #endif
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        HStack(spacing: SPAISpacing.s) {
            quickButton(label: "Reset", systemImage: "arrow.counterclockwise", tint: SPAIColor.primary) {
                appModel.resetWorkflow()
            }
            quickButton(
                label: "History",
                systemImage: "clock.arrow.circlepath",
                tint: SPAIColor.accent,
                isOn: appModel.isVisible("history")
            ) {
                appModel.toggleVisibility("history")
            }
            quickButton(
                label: "Chat",
                systemImage: "bubble.left.and.bubble.right.fill",
                tint: SPAIColor.safe,
                isOn: appModel.isVisible("chat")
            ) {
                appModel.toggleVisibility("chat")
            }
            // Mirrors the status bar's toggle rather than opening blind. Settings is a
            // singleton `Window` now, so a stale flag can at worst re-focus the window
            // that is already open — it can no longer mint a second copy.
            quickButton(
                label: "Settings",
                systemImage: "gearshape.fill",
                tint: .white,
                isOn: appModel.isSettingsWindowOpen
            ) {
                if appModel.isSettingsWindowOpen {
                    dismissWindow(id: "settings")
                    appModel.isSettingsWindowOpen = false
                } else {
                    openWindow(id: "settings")
                    appModel.isSettingsWindowOpen = true
                }
            }
        }
        .padding(SPAISpacing.s + 2)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wrist quick actions")
    }

    /// `isOn` drives a filled state so toggles read as on/off at a glance — the tester tapped
    /// History and had no way to tell whether anything had happened.
    private func quickButton(
        label: String,
        systemImage: String,
        tint: Color,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : tint)
                    .frame(width: 34, height: 34)
                    .background(
                        isOn ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.22)),
                        in: RoundedRectangle(cornerRadius: SPAIRadius.small)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: SPAIRadius.small)
                            .stroke(tint.opacity(isOn ? 0.9 : 0.5), lineWidth: 1)
                    }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        // Reset "worked intermittently" — at 30pt the glyph was the whole target. The
        // standard 44pt minimum plus the label give the gaze somewhere to land.
        .spaiHitTarget(minSize: 56)
        .animation(.easeOut(duration: 0.18), value: isOn)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Preview
#Preview("Wrist Menu Panel") {
    WristMenuPanel(isHandVisible: true)
        .environment(AppModel())
        .padding(40)
        .background(.black)
}
#endif
