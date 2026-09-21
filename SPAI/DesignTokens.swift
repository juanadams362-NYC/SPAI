//
//  DesignTokens.swift
//  SPAI
//

import SwiftUI

/// Unified layout system for SPAI's spatial arc panels.
///
/// At the default visionOS immersive-space rendering scale **1 SwiftUI point ≈ 1 mm** in the
/// physical world (confirmed by the `ptToMeters = 0.001` constant in `PanelDragHandle`).
/// Sizes below are therefore in millimetres as well as points.
///
/// **Panel width rationale**
/// | Panel | Width (pt) | Distance (m) | Horiz. FoV |
/// |-------|-----------|------------|----------|
/// | Status bar | 900 | 1.55 | ~33° |
/// | Workflow timeline | 600 | 1.15 | ~30° |
/// | Standard content | 400 | 1.05–1.30 | 18–22° |
/// | Chat | 320 | 1.30 | ~14° |
///
/// **Button hit-target rationale**
/// Panels using `panelWidth` as their single sizing parameter derive button minimum heights
/// from `panelWidth × 0.13`. Setting `standardWidth = 400` gives `400 × 0.13 = 52 pt` — a
/// comfortable gaze-pinch target at 1–1.3 m (≈ 2.5–3°). Explicit icon buttons (ActionPanel)
/// use `iconButton = 64 pt` because they have no label to widen the visual target.
enum SPAILayout {
    // MARK: — Panel widths

    /// Status bar spanning the full front arc. 1 200 mm at 1.55 m ≈ 44° horizontal —
    /// down from the former 1 440 mm (55°). Layout adjustments inside StatusBarPanel
    /// (tighter HStack spacing, condensed session-time block, compact mode badge) make
    /// the full role-picker + control-button row fit within this width.
    static let barWidth:      CGFloat = 1200

    /// Workflow five-step timeline. 600 mm at 1.15 m ≈ 30° horizontal.
    static let wideWidth:     CGFloat = 600

    /// Standard content panels (detection, event log, guided step, report, history, tour).
    /// 400 mm at 1.05–1.30 m ≈ 18–22°. Yields 400 × 0.13 = 52 pt minimum button height.
    static let standardWidth: CGFloat = 400

    /// Chat panel — message bubbles need less horizontal room. 320 mm at 1.30 m ≈ 14°.
    static let chatWidth:     CGFloat = 320

    /// Simulator-only upload panel — minimal chrome.
    static let compactWidth:  CGFloat = 260

    // MARK: — Button hit targets

    /// Icon-only buttons (ActionPanel column). 64 pt at 1.35 m ≈ 2.7° visual angle.
    static let iconButton:    CGFloat = 64

    /// Vertical padding for text-label buttons. 2 × 14 pt added to the ~22 pt label
    /// line-height → ~50 pt total — safely hittable from all panel viewing distances.
    static let buttonVPad:    CGFloat = 14

    /// Horizontal padding for text-label buttons.
    static let buttonHPad:    CGFloat = 20
}

enum SPAIColor {
    static let primary       = Color(red: 0.00, green: 0.48, blue: 1.00)
    static let secondary     = Color(red: 0.48, green: 0.30, blue: 1.00)
    static let accent        = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let neutralLight  = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let neutralMid    = Color(red: 0.82, green: 0.82, blue: 0.84)
    static let neutralDark   = Color(red: 0.11, green: 0.11, blue: 0.12)

    static let safe          = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let warning       = Color(red: 1.00, green: 0.70, blue: 0.20)
    static let critical      = Color(red: 0.95, green: 0.30, blue: 0.35)
}

enum SPAIRadius {
    static let small: CGFloat   = 12
    static let medium: CGFloat  = 20
    static let large: CGFloat   = 28
    static let pill: CGFloat    = 999
}

enum SPAISpacing {
    static let xs: CGFloat  = 4
    static let s: CGFloat   = 8
    static let m: CGFloat   = 16
    static let l: CGFloat   = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 40
}

/// Minimum hit target plus a gaze response.
///
/// A separate modifier rather than an inline chain so it can read the environment: with Reduce
/// Motion on, the control still highlights under gaze but does not scale or lift. Motion is the
/// affordance here, so it has to degrade to something rather than to nothing.
//struct SPAIHitTarget: ViewModifier {
//    @Environment(\.accessibilityReduceMotion) private var reduceMotion
//
//    let minSize: CGFloat
//    let pop: CGFloat
//
//    func body(content: Content) -> some View {
//        content
//            .frame(minWidth: minSize, minHeight: minSize)
//            .contentShape(Rectangle())
//            .hoverEffect { effect, isActive, _ in
//                effect
//                    .scaleEffect(isActive && !reduceMotion ? pop : 1.0)
//                    .offset(y: isActive && !reduceMotion ? -2 : 0)
//            }
//            .hoverEffect(.highlight)
//            
//            .allowsHitTesting(true)
//            // DIAGNOSTIC — gaze probe only. The tap probe was removed because in visionOS's
//            // indirect pinch model a simultaneousGesture(TapGesture()) on a .plain-style
//            // Button competes with the Button's own recognizer: once the outer TapGesture
//            // fires and calls onEnded, visionOS marks that pinch sequence as "handled" and
//            // the Button's internal recognizer can't advance to recognized state →
//            // MRUIFeedbackTypeButtonWithoutBackgroundTouchDown stalls at ~2 s → action
//            // never fires. Gaze hover alone is safe (read-only, no gesture competition).
//            .onHover { hovering in
//                guard hovering else { return }
//                SPAILog.debug(.ui, "gaze entered a control")
//            }
//    }
//}

struct SPAIGlass: ViewModifier {
    enum Mode { case light, dark }
    let mode: Mode
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                mode == .light
                    ? AnyShapeStyle(.regularMaterial)
                    : AnyShapeStyle(Color.white.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(
                        mode == .light
                            ? Color.white.opacity(0.4)
                            : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

/// Pulses a coloured ring around a button while the guided tour is waiting on exactly
/// that action. Drives its own animation — the caller only toggles `active`.
struct TourHighlightModifier: ViewModifier {
    let active: Bool
    let color: Color
    let cornerRadius: CGFloat

    @State private var glow = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if active {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(color, lineWidth: 2.5)
                        .padding(-4)
                        .opacity(glow ? 1.0 : 0.25)
                        .shadow(color: color, radius: glow ? 8 : 2)
                        .allowsHitTesting(false)   // never steal a tap meant for the button
                }
            }
            .onAppear {
                guard active else { return }
                startPulse()
            }
            .onChange(of: active) { _, isNowActive in
                if isNowActive { startPulse() } else { glow = false }
            }
    }

    private func startPulse() {
        glow = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            glow = true
        }
    }
}

/// A drag-to-reposition handle appended to the bottom of every arc panel.
///
/// The user grabs the pill and drags; the SwiftUI 2-D translation is converted to a world-space
/// SIMD3<Float> offset and forwarded to AppModel. ImmersiveView adds this offset to the panel
/// entity's arc position on each RealityView update pass.
///
/// The hide (×) button collapses the handle to a tiny restore dot so panels that the user never
/// moves don't carry unnecessary visual weight. The preference is persisted per-panel.
struct PanelDragHandle: View {
    let panelID: String
    @Environment(AppModel.self) private var appModel

    /// Accumulated offset from all completed drags this session (local copy that stays in sync
    /// with AppModel; reset implicitly when the immersive space closes and re-creates the view).
    @State private var preDragOffset: SIMD3<Float> = .zero

    /// 1 SwiftUI point ≈ 1 mm at the default visionOS immersive-space viewing distance.
    private let ptToMeters: Float = 0.001

    var body: some View {
        if appModel.isHandleVisible(for: panelID) {
            handleBar
        } else {
            restoreButton
        }
    }

    // MARK: - Handle bar

    private var handleBar: some View {
        HStack(spacing: 0) {
            // Balances the hide button so the grip is centred.
            Color.clear.frame(width: 28, height: 1)

            Spacer()

            // The grip pill — visual cue that this area is draggable.
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 44, height: 4)

            Spacer()

            // Hide button. Plain style keeps pinch-tap behaviour identical to every other
            // panel button and avoids the TapGesture competition risk noted in MEMORY.md.
            Button {
                appModel.setHandleVisible(false, for: panelID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide drag handle")
        }
        .padding(.vertical, SPAISpacing.xs + 2)
        // Full-width hit target so the user can grab anywhere along the bar.
        .contentShape(Rectangle())
        .gesture(
            // minimumDistance: 5 prevents a stationary pinch on the bar from triggering a drag
            // and interfering with the hide button sitting inside the same parent view.
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    let dx =  Float(value.translation.width)  * ptToMeters
                    let dy = -Float(value.translation.height) * ptToMeters   // SwiftUI Y is down
                    appModel.setDragOffset(preDragOffset + SIMD3<Float>(dx, dy, 0), for: panelID)
                }
                .onEnded { value in
                    let dx =  Float(value.translation.width)  * ptToMeters
                    let dy = -Float(value.translation.height) * ptToMeters
                    preDragOffset += SIMD3<Float>(dx, dy, 0)
                }
        )
        .accessibilityLabel("Drag handle. Drag to reposition panel.")
    }

    // MARK: - Restore button (shown when handle is hidden)

    private var restoreButton: some View {
        HStack {
            Spacer()
            Button {
                appModel.setHandleVisible(true, for: panelID)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(width: 44, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show drag handle")
        }
        .padding(.horizontal, SPAISpacing.s)
    }
}

// MARK: - WCAG contrast helpers

extension Color {
    /// WCAG 2.1 relative luminance for an sRGB colour (range 0 = black … 1 = white).
    ///
    /// Uses `Color.resolve(in:)` so dynamic/semantic colours (`.primary`, system greys, etc.)
    /// are correctly evaluated under the current environment before the maths runs.
    func relativeLuminance(in environment: EnvironmentValues) -> Double {
        let r = resolve(in: environment)
        // Linearise each sRGB channel per the IEC 61966-2-1 piecewise function.
        func lin(_ c: Float) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r.red) + 0.7152 * lin(r.green) + 0.0722 * lin(r.blue)
    }

    /// Returns `.white` or `.black` — whichever gives higher WCAG 2.1 contrast ratio
    /// against `self` as a background colour.
    ///
    /// The crossover luminance is ≈ 0.179, derived by solving the WCAG contrast-ratio
    /// equation for the point where white and black text reach equal contrast:
    ///   (1.05) / (L + 0.05) = (L + 0.05) / (0.05)  →  L ≈ 0.179
    /// Below that value white text wins; above it black text wins.
    func accessibleForeground(in environment: EnvironmentValues) -> Color {
        relativeLuminance(in: environment) > 0.179 ? .black : .white
    }
}

extension View {
    func spaiGlass(_ mode: SPAIGlass.Mode = .dark, radius: CGFloat = SPAIRadius.large) -> some View {
        modifier(SPAIGlass(mode: mode, radius: radius))
    }

    /// Guarantees a control meets the platform minimum hit-target size and shows a visible
    /// gaze-hover response, regardless of how small its visual content is. The extra hit area
    /// is invisible — it only widens what counts as "on" the control, it doesn't resize it.
    ///
    /// The highlight alone read as too subtle in testing ("nothing signals they are tappable"),
    /// so the control also lifts and scales slightly under gaze. `pop` is the scale at rest→hover.
//    func spaiHitTarget(minSize: CGFloat = 44, pop: CGFloat = 1.08) -> some View {
//        modifier(SPAIHitTarget(minSize: minSize, pop: pop))
//    }

    /// Entrance used by every panel that can be toggled on. The panel scales up from the
    /// direction it was opened from and fades in, so a panel that appears outside the user's
    /// current field of view still reads as "something just opened over there".
    func spaiPanelEntrance(isVisible: Bool) -> some View {
        self
            .scaleEffect(isVisible ? 1.0 : 0.86)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isVisible)
    }

    /// Adds a pulsing glow ring to a button when the guided tour is waiting on it.
    /// Pass the button's own `cornerRadius` to match the ring shape to the button shape.
    func tourHighlight(
        active: Bool,
        color: Color = SPAIColor.primary,
        cornerRadius: CGFloat = SPAIRadius.small
    ) -> some View {
        modifier(TourHighlightModifier(active: active, color: color, cornerRadius: cornerRadius))
    }

    func spaiPanelBackground(opacity: Double, cornerRadius: CGFloat = SPAIRadius.large) -> some View {
        self.background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(opacity * 0.6))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        )
    }
}
