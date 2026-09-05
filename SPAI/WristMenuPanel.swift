import SwiftUI
import simd

#if os(visionOS)
/// A compact quick-action menu that rides the user's right wrist, summoned by holding the
/// wrist as if checking the time.
///
/// World placement (tracking the live wrist pose vs. a fixed fallback position) is owned by
/// ImmersiveView, which repositions this attachment's RealityKit entity every frame — this view
/// only decides whether it should be visible right now, and reports what each tap did.
struct WristMenuPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the wrist is currently held in the summoning posture. Passed as a plain value,
    /// not a closure: an earlier version called a closure from `body` and wrote to `@State` as
    /// a side effect, which SwiftUI does not re-evaluate on its own — so once the arm left the
    /// frame nothing invalidated the view and the panel stayed frozen on screen.
    let isPresented: Bool

    var body: some View {
        panelContent
            .opacity(shouldShowPanel ? 1 : 0)
            .scaleEffect(shouldShowPanel ? 1 : 0.9)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.22), value: shouldShowPanel)
            .allowsHitTesting(shouldShowPanel)
    }

    private var shouldShowPanel: Bool {
        guard appModel.wristMenusEnabled else { return false }
        #if targetEnvironment(simulator)
        // Hand tracking never runs in the simulator, so pin the panel visible there.
        return true
        #else
        return isPresented
        #endif
    }

    // MARK: - Panel Content

    /// Laid out 2×2 rather than as a single row of four.
    ///
    /// A row of four is ~15 cm wide, and it hangs off the side of the forearm — so between the
    /// stand-off distance and the panel itself it reached ~30 cm into the space in front of the
    /// user's hands, which is the "physically in the way while working" complaint. A square
    /// tile is half as wide for the same four controls.
    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                quickButton(label: "Reset", systemImage: "arrow.counterclockwise", tint: SPAIColor.primary) {
                    appModel.resetWorkflow()
                    appModel.announce("Workflow reset", icon: "arrow.counterclockwise")
                }
                quickButton(
                    label: "History",
                    systemImage: "clock.arrow.circlepath",
                    tint: SPAIColor.accent,
                    isOn: appModel.isVisible("history")
                ) {
                    appModel.toggleVisibility("history")
                }
            }
            HStack(spacing: 4) {
                quickButton(
                    label: "Chat",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    tint: SPAIColor.safe,
                    isOn: appModel.isVisible("chat")
                ) {
                    appModel.toggleVisibility("chat")
                }
                quickButton(
                    label: "Settings",
                    systemImage: "gearshape.fill",
                    tint: SPAIColor.secondary,
                    isOn: appModel.isSettingsWindowOpen
                ) {
                    // One shared decision point, debounced, so a double gaze-pinch can't
                    // read as open-then-close — and can't spawn a second window.
                    switch appModel.requestSettingsToggle() {
                    case .open:   openWindow(id: "settings")
                    case .close:  dismissWindow(id: "settings")
                    case .ignore: break
                    }
                }
            }

            ActionFeedbackStrip()
        }
        .padding(7)
        .spaiPanelBackground(opacity: appModel.panelOpacity, cornerRadius: SPAIRadius.medium)
        .ledBorder(cornerRadius: SPAIRadius.medium, lineWidth: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wrist quick actions")
        .accessibilityHint("Raise and turn your right wrist toward you to show this menu")
    }

    /// Compact by default and enlarged under gaze.
    ///
    /// visionOS never tells an app where the user is looking — hover effects are composited by
    /// the system out of process — so the label cannot literally be revealed on glance. Instead
    /// it is always drawn small and the whole control, label included, scales up under the
    /// system hover effect. That reads as the words popping out while keeping the resting size
    /// down, which is what the menu needed.
    private func quickButton(
        label: String,
        systemImage: String,
        tint: Color,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : tint)
                    .frame(width: 26, height: 26)
                    .background(
                        isOn ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.20)),
                        in: RoundedRectangle(cornerRadius: SPAIRadius.small - 4)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: SPAIRadius.small - 4)
                            .stroke(tint.opacity(isOn ? 0.9 : 0.45), lineWidth: 1)
                    }
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        // 44pt is the accessibility floor and also what made the flaky Reset button reliable;
        // the visual content is smaller than the target, which is the point.
        .spaiHitTarget(minSize: 44, pop: 1.22)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.18), value: isOn)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The line under the wrist buttons that says what the last tap actually did.
///
/// Placed here because the wrist is where the user is already looking when they press one of
/// these — a confirmation anywhere else in the room would have the same discoverability
/// problem as the panels it is describing.
struct ActionFeedbackStrip: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a confirmation stays up.
    private let lifetime: TimeInterval = 2.2

    @State private var shown: AppModel.ActionFeedback?

    var body: some View {
        Group {
            if let shown {
                HStack(spacing: 4) {
                    Image(systemName: shown.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(shown.message)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(SPAIColor.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SPAIColor.accent.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(SPAIColor.accent.opacity(0.45), lineWidth: 1))
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.85).combined(with: .opacity)
                )
            }
        }
        .frame(height: 20)
        .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.7), value: shown)
        // Announced to VoiceOver too — this is the app telling you what just happened, which
        // is exactly the sort of thing a screen reader user needs and cannot infer from motion.
        .accessibilityLabel(shown.map { "\($0.message)" } ?? "")
        .accessibilityHidden(shown == nil)
        .onChange(of: appModel.lastAction) { _, action in
            guard let action else { return }
            shown = action
            Task {
                try? await Task.sleep(for: .seconds(lifetime))
                // Only clear if nothing newer arrived while we were waiting.
                if shown?.at == action.at { shown = nil }
            }
        }
    }
}

// MARK: - Preview
#Preview("Wrist Menu Panel") {
    WristMenuPanel(isPresented: true)
        .environment(AppModel())
        .padding(40)
        .background(.black)
}
#endif
