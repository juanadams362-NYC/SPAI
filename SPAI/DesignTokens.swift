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

/// Type sizes for panels in the immersive space.
///
/// Panels float a metre or more away, so nothing a user is meant to read is
/// set below 13pt, and secondary text is dimmed with opacity no lower than
/// 0.7 — smaller or fainter than that stops being legible at arm's length.
enum SPAIFont {
    /// Panel section label, e.g. "DETECTION".
    static let eyebrow = Font.system(size: 13, weight: .bold, design: .monospaced)
    /// The one thing a panel is telling you.
    static let headline = Font.system(size: 20, weight: .semibold)
    /// Spoken-length instructions.
    static let instruction = Font.system(size: 19, weight: .medium)
    static let body = Font.system(size: 16)
    static let bodyStrong = Font.system(size: 16, weight: .semibold)
    static let label = Font.system(size: 15, weight: .medium)
    static let caption = Font.system(size: 13)
    static let value = Font.system(size: 15, weight: .semibold, design: .monospaced)
    static let button = Font.system(size: 15, weight: .semibold)
}

enum SPAIText {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.78)
    static let tertiary = Color.white.opacity(0.7)
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
    /// gaze-hover highlight, regardless of how small its visual content is. The extra hit area
    /// is invisible — it only widens what counts as "on" the control, it doesn't resize it.
    func spaiHitTarget(minSize: CGFloat = 44) -> some View {
        self
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }

    /// Standard chrome for a panel in the immersive space: background,
    /// border, and the guide's spotlight.
    ///
    /// - Parameters:
    ///   - id: The panel's `PanelID`, so the guide can point at it. Pass nil
    ///     for panels the guide never targets.
    ///   - border: The panel's own alert state. Leave `.normal` unless the
    ///     panel has something urgent to say.
    func spaiPanel(_ id: String? = nil, border: BorderState = .normal) -> some View {
        modifier(SPAIPanelChrome(id: id, border: border))
    }

    /// Small uppercase section label used at the top of every panel.
    func spaiEyebrow() -> some View {
        self.font(SPAIFont.eyebrow)
            .tracking(1.5)
            .foregroundStyle(SPAIText.secondary)
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

/// The shared look of every immersive panel, and the one place the guide's
/// spotlight is drawn.
///
/// When the guide points at a panel, that panel's border lights up and it
/// lifts slightly. During the tour, every other panel also fades back, so
/// there is exactly one thing in the room asking to be looked at.
struct SPAIPanelChrome: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let id: String?
    let border: BorderState

    private var isSpotlit: Bool {
        guard let id else { return false }
        return appModel.spotlightPanel == id
    }

    private var isDimmed: Bool {
        appModel.isTourActive && appModel.spotlightPanel != nil && !isSpotlit
    }

    func body(content: Content) -> some View {
        content
            .spaiPanelBackground(opacity: appModel.panelOpacity)
            // A panel's own warning outranks the guide's highlight.
            .ledBorder(border == .normal && isSpotlit ? .attention : border,
                       cornerRadius: SPAIRadius.large,
                       lineWidth: isSpotlit ? 3 : 1.5)
            .scaleEffect(isSpotlit ? 1.04 : 1)
            .opacity(isDimmed ? 0.3 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isSpotlit)
            .animation(.easeInOut(duration: 0.35), value: isDimmed)
    }
}
