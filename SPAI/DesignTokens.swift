//
//  DesignTokens.swift
//  SPAI
//

import SwiftUI

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

// Spacing tuned for headset viewing (~1–1.5 m working distance).
// All values increased ~25 % over typical screen defaults.
enum SPAISpacing {
    static let xs: CGFloat  = 6
    static let s: CGFloat   = 10
    static let m: CGFloat   = 20
    static let l: CGFloat   = 28
    static let xl: CGFloat  = 40
    static let xxl: CGFloat = 48
}

// Minimum legible font sizes at headset viewing distance.
// Below SPAITextSize.caption, text is hard to read from 1 m+.
enum SPAITextSize {
    static let micro: CGFloat       = 11   // decorative / monospaced status labels only
    static let caption: CGFloat     = 14   // absolute minimum for readable body text
    static let footnote: CGFloat    = 15
    static let body: CGFloat        = 17
    static let subheadline: CGFloat = 19
    static let headline: CGFloat    = 22
    static let title: CGFloat       = 28
    static let largeTitle: CGFloat  = 36
}

// Consistent animation values. Use these instead of inline durations so every
// button and panel transition feels like the same product.
enum SPAIAnimation {
    // Scale factor applied when a button is looked at (spaiLookAtScale).
    static let hoverScale: CGFloat        = 1.06
    // Spring used for the look-at pop.
    static let hover: Animation           = .spring(response: 0.18, dampingFraction: 0.72)
    // Easing used for panel appear/disappear transitions.
    static let panelTransition: Animation = .easeInOut(duration: 0.22)
}

private struct LookAtScaleModifier: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? SPAIAnimation.hoverScale : 1.0)
            .animation(SPAIAnimation.hover, value: hovered)
            .onHover { hovered = $0 }
    }
}

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

extension View {
    func spaiGlass(_ mode: SPAIGlass.Mode = .dark, radius: CGFloat = SPAIRadius.large) -> some View {
        modifier(SPAIGlass(mode: mode, radius: radius))
    }

    /// Guarantees a control meets the minimum visionOS hit-target size (60 pt) and shows a
    /// lift hover effect so the tester can tell the control is interactive. The extra hit area
    /// is invisible — it only widens what counts as "on" the control.
    func spaiHitTarget(minSize: CGFloat = 60) -> some View {
        self
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
            .hoverEffect(.lift)
    }

    /// Adds a subtle scale-up animation when the control is looked at, on top of any
    /// system hover effect. Use on non-Button controls that need interactive affordance.
    func spaiLookAtScale() -> some View {
        modifier(LookAtScaleModifier())
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
