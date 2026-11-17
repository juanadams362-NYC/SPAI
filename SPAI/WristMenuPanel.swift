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

    let isHandVisibleProvider: () -> Bool

    @State private var lastVisibleAt: Date = .distantPast
    private let visibilityHoldSeconds: TimeInterval = 0.3

    var body: some View {
        panelContent
            .opacity(shouldShowPanel ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: shouldShowPanel)
    }

    // MARK: - Derived State

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var shouldShowPanel: Bool {
        if isSimulator { return true }
        let visible = isHandVisibleProvider()
        if visible { lastVisibleAt = Date() }
        return visible || Date().timeIntervalSince(lastVisibleAt) < visibilityHoldSeconds
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        HStack(spacing: 10) {
            quickButton(label: "Reset", systemImage: "arrow.counterclockwise", tint: SPAIColor.primary) {
                appModel.resetWorkflow()
            }
            quickButton(label: "History", systemImage: "clock.arrow.circlepath", tint: SPAIColor.accent) {
                appModel.toggleVisibility("history")
            }
            quickButton(label: "Ask SPAI", systemImage: "sparkles", tint: SPAIColor.secondary) {
                appModel.toggleVisibility("chat")
            }
            quickButton(label: "Settings", systemImage: "gearshape.fill", tint: .white) {
                openWindow(id: "settings")
            }
        }
        .padding(8)
        .spaiPanelBackground(opacity: appModel.panelOpacity, cornerRadius: 34)
        .ledBorder(cornerRadius: 34, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wrist quick actions")
    }

    private func quickButton(label: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.spaiIcon(tint: tint, size: 44))
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Preview
#Preview("Wrist Menu Panel") {
    WristMenuPanel(isHandVisibleProvider: { true })
        .environment(AppModel())
        .padding(40)
        .background(.black)
}
#endif
