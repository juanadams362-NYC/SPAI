import SwiftUI
import simd

#if os(visionOS)
/// A floating quick-action menu that follows the user's wrist on device, with a simulator fallback.
struct WristMenuPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    // Hand tracking service is assumed to exist in the environment elsewhere in the app.
    // We avoid importing or referencing specific types that may not be visible here; instead we
    // accept wrist pose via injectable closures to keep this view decoupled and previewable.
    let wristPoseProvider: () -> (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)?
    let isHandVisibleProvider: () -> Bool

    // Configuration offsets to place the panel slightly above/inside the wrist area.
    var wristOffsetLocal: SIMD3<Float> = SIMD3<Float>(x: 0.04, y: 0.02, z: 0.0)

    // Simulator fallback placement in immersive space (lower-left-ish, facing user).
    var simulatorFallbackPosition: SIMD3<Float> = SIMD3<Float>(x: -0.6, y: -0.3, z: -1.0)

    @State private var lastVisibleAt: Date = .distantPast
    private let visibilityHoldSeconds: TimeInterval = 0.3

    var body: some View {
        // The visual content of the panel
        panelContent
            .opacity(shouldShowPanel ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: shouldShowPanel)
            // Position/orientation for visionOS: use a RealityView/Immersive container later.
            // Here we expose transform via view modifiers that ImmersiveView can consume.
            .modifier(WristSpatialTransformModifier(transform: currentTransform))
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

    private var currentTransform: WristSpatialTransformModifier.Transform {
        if isSimulator {
            // Fallback: place at a fixed location facing the user along -Z with up = +Y
            let pos = simulatorFallbackPosition
            let forward = normalize(SIMD3<Float>(0, 0, 1)) // panel faces the user (toward camera)
            let up = SIMD3<Float>(0, 1, 0)
            return .init(position: pos, forward: forward, up: up)
        }

        if let pose = wristPoseProvider() {
            // Offset slightly from wrist in its local frame.
            // Compose world-space position: p_world = p_wrist + right*dx + up*dy + forward*dz
            // We approximate right = normalize(cross(up, forward)).
            let right = normalize(cross(pose.up, pose.forward))
            let pos = pose.position + right * wristOffsetLocal.x + pose.up * wristOffsetLocal.y + pose.forward * wristOffsetLocal.z
            return .init(position: pos, forward: pose.forward, up: pose.up)
        }

        // If no data yet, keep it hidden at origin to avoid flashing.
        return .init(position: SIMD3<Float>(repeating: 0), forward: SIMD3<Float>(0, 0, 1), up: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: SPAISpacing.s + 4) {
            HStack(spacing: SPAISpacing.s) {
                quickButton(label: "Reset", systemImage: "arrow.counterclockwise", tint: SPAIColor.primary) {
                    appModel.resetWorkflow()
                }
                quickButton(label: "History", systemImage: "clock.arrow.circlepath", tint: SPAIColor.accent) {
                    appModel.toggleVisibility("history")
                }
                quickButton(label: "Chat", systemImage: "bubble.left.and.bubble.right.fill", tint: SPAIColor.safe) {
                    appModel.toggleVisibility("chat")
                }
                quickButton(label: "Settings", systemImage: "gearshape.fill", tint: .white) {
                    openWindow(id: "settings")
                }
            }
        }
        .padding(SPAISpacing.s)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wrist quick actions")
    }

    private func quickButton(label: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: SPAIRadius.small)
                        .stroke(tint.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Spatial Transform Adapter
/// A lightweight adapter that carries a spatial transform (position + orientation) so the
/// immersive scene can read it and place the panel accordingly. This avoids touching ImmersiveView
/// in this change; you can query this environment value from your scene or use a custom container.
struct WristSpatialTransformModifier: ViewModifier {
    struct Transform: Equatable {
        var position: SIMD3<Float>
        var forward: SIMD3<Float>
        var up: SIMD3<Float>
    }

    var transform: Transform

    func body(content: Content) -> some View {
        content
            .environment(\.wristPanelTransform, transform)
    }
}

private struct WristPanelTransformKey: EnvironmentKey {
    static let defaultValue: WristSpatialTransformModifier.Transform = .init(position: SIMD3<Float>(repeating: 0), forward: SIMD3<Float>(0, 0, 1), up: SIMD3<Float>(0, 1, 0))
}

extension EnvironmentValues {
    var wristPanelTransform: WristSpatialTransformModifier.Transform {
        get { self[WristPanelTransformKey.self] }
        set { self[WristPanelTransformKey.self] = newValue }
    }
}

// MARK: - Preview
#Preview("Wrist Menu Panel") {
    // Mock providers for preview
    WristMenuPanel(
        wristPoseProvider: {
            // Simulate a pose 1m in front of the viewer
            let position = SIMD3<Float>(0, 0, -1)
            let forward = SIMD3<Float>(0, 0, 1)
            let up = SIMD3<Float>(0, 1, 0)
            return (position, forward, up)
        },
        isHandVisibleProvider: { true }
    )
    .padding(40)
    .background(.black)
}
#endif

