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

enum SPAISpacing {
    static let xs: CGFloat  = 4
    static let s: CGFloat   = 8
    static let m: CGFloat   = 16
    static let l: CGFloat   = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 40
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

    /// Guarantees a control meets the platform minimum hit-target size and shows a visible
    /// gaze-hover response, regardless of how small its visual content is. The extra hit area
    /// is invisible — it only widens what counts as "on" the control, it doesn't resize it.
    ///
    /// The highlight alone read as too subtle in testing ("nothing signals they are tappable"),
    /// so the control also lifts and scales slightly under gaze. `pop` is the scale at rest→hover.
    func spaiHitTarget(minSize: CGFloat = 44, pop: CGFloat = 1.08) -> some View {
        self
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
            .hoverEffect { effect, isActive, _ in
                effect
                    .scaleEffect(isActive ? pop : 1.0)
                    .offset(y: isActive ? -2 : 0)
            }
            .hoverEffect(.highlight)
    }

    /// Entrance used by every panel that can be toggled on. The panel scales up from the
    /// direction it was opened from and fades in, so a panel that appears outside the user's
    /// current field of view still reads as "something just opened over there".
    func spaiPanelEntrance(isVisible: Bool) -> some View {
        self
            .scaleEffect(isVisible ? 1.0 : 0.86)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isVisible)
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
