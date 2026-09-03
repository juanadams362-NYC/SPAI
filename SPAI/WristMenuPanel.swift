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

    let isHandVisible: Bool

    @State private var fadingOut = false
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        panelContent
            .opacity(shouldShowPanel ? 1 : 0)
            .animation(SPAIAnimation.panelTransition, value: shouldShowPanel)
            .onChange(of: isHandVisible) { _, visible in
                if visible {
                    fadeTask?.cancel()
                    fadeTask = nil
                    fadingOut = false
                } else {
                    // Grace period: keep panel visible for 2 s then fade out
                    fadeTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        fadingOut = true
                    }
                }
            }
    }

    // MARK: - Derived State

    private var shouldShowPanel: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return isHandVisible || !fadingOut
        #endif
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        HStack(spacing: SPAISpacing.s) {
            quickButton(label: "Reset", systemImage: "arrow.counterclockwise", tint: SPAIColor.critical, size: 40) {
                appModel.resetWorkflow()
            }
            quickButton(label: "History", systemImage: "clock.arrow.circlepath", tint: SPAIColor.accent) {
                appModel.toggleVisibility("history")
            }
            quickButton(label: "Chat", systemImage: "bubble.left.and.bubble.right.fill", tint: SPAIColor.safe) {
                appModel.toggleVisibility("chat")
            }
            quickButton(label: "Settings", systemImage: "gearshape.fill", tint: .white) {
                if appModel.isSettingsWindowOpen {
                    dismissWindow(id: "settings")
                    appModel.isSettingsWindowOpen = false
                } else {
                    openWindow(id: "settings")
                    appModel.isSettingsWindowOpen = true
                }
            }
        }
        .padding(SPAISpacing.m)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wrist quick actions")
    }

    private func quickButton(
        label: String,
        systemImage: String,
        tint: Color,
        size: CGFloat = 34,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: SPAITextSize.body, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: SPAIRadius.small)
                        .stroke(tint.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .spaiHitTarget()
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Preview
#Preview("Wrist Menu Panel") {
    WristMenuPanel(isHandVisible: true)
        .padding(40)
        .background(.black)
}
#endif
