//
//  DesignTokens.swift
//  SPAI
//
//  The SPAI design system — "Sterile Aurora".
//
//  Every window and spatial panel pulls its color, type, spacing and chrome from
//  here so the product reads as one system. The palette is built for passthrough:
//  luminous cyan for the brand and primary actions, violet for anything AI, and
//  status colors (green / amber / rose) that are never reused for decoration —
//  so when something turns rose, it always means contamination.
//

import SwiftUI

// MARK: - Color

extension Color {
    /// sRGB hex literal, e.g. `Color(hex: 0x22D3EE)`.
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum SPAIColor {
    // Brand
    /// Sterile cyan — brand color for icons, strokes, progress and focus.
    static let primary       = Color(hex: 0x22D3EE)
    /// Luminous cyan — fills of primary buttons and live highlights.
    static let primaryBright = Color(hex: 0x67E8F9)
    /// Aurora teal — gradient partner for the brand cyan.
    static let teal          = Color(hex: 0x5EEAD4)
    /// AI violet — Ask SPAI and anything model-driven.
    static let secondary     = Color(hex: 0xA78BFA)
    static let secondaryDeep = Color(hex: 0x8B5CF6)
    /// Soft sky — informational accents that shouldn't compete with the brand.
    static let accent        = Color(hex: 0x7DD3FC)

    // Status (reserved for meaning, never decoration)
    static let safe          = Color(hex: 0x4ADE80)
    static let warning       = Color(hex: 0xFBBF24)
    static let critical      = Color(hex: 0xFB7185)
    static let criticalDeep  = Color(hex: 0xF43F5E)

    // Neutrals
    static let ink           = Color(hex: 0x07111D)   // smoked-glass tint
    /// Text and icons placed on bright fills (primary / success / danger buttons).
    static let onFill        = Color(hex: 0x05131C)
    static let neutralLight  = Color(hex: 0xE2E8F0)
    static let neutralMid    = Color(hex: 0x94A3B8)
    static let neutralDark   = Color(hex: 0x0B1220)

    // Text on glass
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.74)
    static let textTertiary  = Color.white.opacity(0.52)

    // Surfaces inside panels
    static let surface       = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.10)
    static let hairline      = Color.white.opacity(0.10)
    static let hairlineStrong = Color.white.opacity(0.18)
}

enum SPAIGradient {
    /// Primary action fill.
    static let brand = LinearGradient(
        colors: [SPAIColor.primaryBright, SPAIColor.teal],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Brand-to-AI sweep for the logo, headline accents and progress.
    static let aurora = LinearGradient(
        colors: [SPAIColor.primaryBright, SPAIColor.primary, SPAIColor.secondary],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Ask SPAI / AI moments.
    static let ai = LinearGradient(
        colors: [Color(hex: 0xC4B5FD), SPAIColor.secondary],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let success = LinearGradient(
        colors: [Color(hex: 0x86EFAC), SPAIColor.safe],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let danger = LinearGradient(
        colors: [Color(hex: 0xFDA4AF), SPAIColor.critical],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let warning = LinearGradient(
        colors: [Color(hex: 0xFDE68A), SPAIColor.warning],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Type

enum SPAIFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    /// Big numbers: risk %, timers, KPIs.
    static func metric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static let eyebrow   = Font.system(size: 12, weight: .semibold)
    static let title     = Font.system(size: 22, weight: .bold)
    static let headline  = Font.system(size: 17, weight: .semibold)
    static let body      = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 16, weight: .medium)
    static let callout   = Font.system(size: 14, weight: .regular)
    static let calloutMedium = Font.system(size: 14, weight: .medium)
    static let caption   = Font.system(size: 12, weight: .medium)
    static let mono      = Font.system(size: 12, weight: .medium, design: .monospaced)
}

// MARK: - Shape & space

enum SPAIRadius {
    static let xsmall: CGFloat  = 8
    static let small: CGFloat   = 12
    static let medium: CGFloat  = 18
    static let large: CGFloat   = 28
    static let window: CGFloat  = 44
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

// MARK: - Glass & panel chrome

struct SPAIGlass: ViewModifier {
    enum Mode { case light, dark }
    let mode: Mode
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(mode == .light ? SPAIColor.surfaceStrong : SPAIColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(mode == .light ? SPAIColor.hairlineStrong : SPAIColor.hairline, lineWidth: 1)
            }
    }
}

extension View {
    /// Inset card used inside windows and panels.
    func spaiGlass(_ mode: SPAIGlass.Mode = .dark, radius: CGFloat = SPAIRadius.large) -> some View {
        modifier(SPAIGlass(mode: mode, radius: radius))
    }

    /// Guarantees a control meets the platform minimum hit-target size and shows a visible
    /// gaze-hover highlight, regardless of how small its visual content is. The extra hit area
    /// is invisible — it only widens what counts as "on" the control, it doesn't resize it.
    func spaiHitTarget(minSize: CGFloat = 44, cornerRadius: CGFloat = SPAIRadius.small) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }

    /// Smoked-glass spatial panel: native visionOS glass, a user-adjustable ink tint for
    /// legibility over bright rooms, a soft top sheen and a hairline edge.
    func spaiPanelBackground(opacity: Double, cornerRadius: CGFloat = SPAIRadius.large) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background {
                ZStack {
                    shape.fill(SPAIColor.ink.opacity(opacity * 0.6))
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), Color.white.opacity(0)],
                            startPoint: .top, endPoint: .center
                        )
                    )
                    shape.strokeBorder(SPAIColor.hairline, lineWidth: 1)
                }
            }
            .glassBackgroundEffect(in: shape)
    }

    /// Full-window chrome for the Home, Settings and Upload windows.
    func spaiWindowBackground(cornerRadius: CGFloat = SPAIRadius.window, aurora: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background { AppBackground(showsAurora: aurora) }
            .clipShape(shape)
            .glassBackgroundEffect(in: shape)
    }

    /// Small uppercase label that sits above a section or value.
    func spaiEyebrow(_ color: Color = SPAIColor.textTertiary) -> some View {
        self
            .font(SPAIFont.eyebrow)
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Buttons

/// The one button style for the app.
///
/// Bright fills (`primary`, `success`, `danger`) carry dark ink text for maximum contrast and
/// are reserved for the single most important action in a view. `tinted` and `glass` are for
/// everything else, so the primary action always stands out.
struct SPAIButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case success
        case danger
        case tinted(Color)
        case glass
        case ghost
    }

    enum Size {
        case small, regular, large
    }

    var variant: Variant = .primary
    var size: Size = .regular
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SPAIButtonBody(configuration: configuration, variant: variant, size: size, fullWidth: fullWidth)
    }
}

private struct SPAIButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: SPAIButtonStyle.Variant
    let size: SPAIButtonStyle.Size
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .labelStyle(SPAIButtonLabelStyle(iconColor: iconColor, spacing: size == .large ? 12 : 8))
            .font(font)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil, minHeight: height)
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
            .shadow(color: glow, radius: size == .large ? 18 : 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
    }

    /// Bright variants fall back to quiet glass while disabled so they never look tappable.
    private var isBright: Bool {
        switch variant {
        case .primary, .success, .danger: return true
        default: return false
        }
    }

    private var fill: AnyShapeStyle {
        guard isEnabled || !isBright else { return AnyShapeStyle(SPAIColor.surface) }
        switch variant {
        case .primary:          return AnyShapeStyle(SPAIGradient.brand)
        case .success:          return AnyShapeStyle(SPAIGradient.success)
        case .danger:           return AnyShapeStyle(SPAIGradient.danger)
        case .tinted(let tint): return AnyShapeStyle(tint.opacity(isEnabled ? 0.18 : 0.08))
        case .glass:            return AnyShapeStyle(SPAIColor.surfaceStrong)
        case .ghost:            return AnyShapeStyle(Color.clear)
        }
    }

    private var stroke: Color {
        if !isEnabled { return SPAIColor.hairline }
        switch variant {
        case .primary, .success, .danger: return Color.white.opacity(0.45)
        case .tinted(let tint):           return tint.opacity(0.45)
        case .glass:                      return SPAIColor.hairlineStrong
        case .ghost:                      return Color.clear
        }
    }

    private var foreground: Color {
        if !isEnabled { return SPAIColor.textTertiary }
        return isBright ? SPAIColor.onFill : SPAIColor.textPrimary
    }

    private var iconColor: Color {
        if !isEnabled { return SPAIColor.textTertiary }
        switch variant {
        case .primary, .success, .danger: return SPAIColor.onFill
        case .tinted(let tint):           return tint
        case .glass:                      return Color.white.opacity(0.9)
        case .ghost:                      return SPAIColor.primaryBright
        }
    }

    private var glow: Color {
        guard isEnabled else { return .clear }
        switch variant {
        case .primary: return SPAIColor.primaryBright.opacity(0.35)
        case .success: return SPAIColor.safe.opacity(0.30)
        case .danger:  return SPAIColor.critical.opacity(0.40)
        default:       return .clear
        }
    }

    private var font: Font {
        switch size {
        case .small:   return .system(size: 13, weight: .semibold)
        case .regular: return .system(size: 15, weight: .semibold)
        case .large:   return .system(size: 20, weight: .semibold)
        }
    }

    private var height: CGFloat {
        switch size {
        case .small:   return 36
        case .regular: return 46
        case .large:   return 64
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small:   return 12
        case .regular: return 18
        case .large:   return 30
        }
    }

    private var radius: CGFloat {
        switch size {
        case .small:   return 10
        case .regular: return 14
        case .large:   return 20
        }
    }
}

/// Lets a button color its SF Symbol independently of its title.
struct SPAIButtonLabelStyle: LabelStyle {
    var iconColor: Color
    var spacing: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
                .foregroundStyle(iconColor)
            configuration.title
        }
    }
}

/// Circular icon-only button used in docks, wrist menus and the chat bar.
struct SPAIIconButtonStyle: ButtonStyle {
    var tint: Color = .white
    var size: CGFloat = 44
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SPAIIconButtonBody(configuration: configuration, tint: tint, size: size, filled: filled)
    }
}

private struct SPAIIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let size: CGFloat
    let filled: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(isEnabled ? (filled ? SPAIColor.onFill : tint) : SPAIColor.textTertiary)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay { Circle().strokeBorder(isEnabled ? tint.opacity(filled ? 0.6 : 0.4) : SPAIColor.hairline, lineWidth: 1) }
            .shadow(color: (filled && isEnabled) ? tint.opacity(0.4) : .clear, radius: 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
    }

    private var fill: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(SPAIColor.surface) }
        return filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.16))
    }
}

extension ButtonStyle where Self == SPAIButtonStyle {
    static func spai(
        _ variant: SPAIButtonStyle.Variant = .primary,
        size: SPAIButtonStyle.Size = .regular,
        fullWidth: Bool = false
    ) -> SPAIButtonStyle {
        SPAIButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == SPAIIconButtonStyle {
    static func spaiIcon(tint: Color = .white, size: CGFloat = 44, filled: Bool = false) -> SPAIIconButtonStyle {
        SPAIIconButtonStyle(tint: tint, size: size, filled: filled)
    }
}

// MARK: - Building blocks

/// Consistent panel header: tinted icon tile, uppercase title, optional trailing accessory.
struct PanelHeader<Trailing: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let trailing: Trailing

    init(_ title: String, icon: String, tint: Color = SPAIColor.primary, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(_ title: String, icon: String, tint: Color = SPAIColor.primary) {
        self.init(title, icon: icon, tint: tint) { EmptyView() }
    }
}

/// Capsule status chip. `live` swaps the icon for a pulsing dot.
struct SPAIChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .white
    var live: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if live {
                LiveDot(color: tint, size: 7)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1) }
    }
}

/// A status dot with a soft radar pulse — used anywhere something is "live".
struct LiveDot: View {
    var color: Color
    var size: CGFloat = 8
    var animating: Bool = true

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color.opacity(0.5))
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : 0.9)
            }
            .shadow(color: color.opacity(0.8), radius: size * 0.4)
            .onAppear {
                guard animating else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Compact labelled value used for environment readings and report stats.
struct MetricTile: View {
    let label: String
    let value: String
    var icon: String? = nil
    var tint: Color = SPAIColor.primary
    var valueColor: Color = SPAIColor.textPrimary
    var status: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(SPAIColor.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let status {
                    Circle()
                        .fill(status)
                        .frame(width: 6, height: 6)
                        .shadow(color: status.opacity(0.8), radius: 3)
                }
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
    }
}

/// Hairline separator.
struct SPAIDivider: View {
    var vertical: Bool = false

    var body: some View {
        if vertical {
            Rectangle().fill(SPAIColor.hairlineStrong).frame(width: 1, height: 32)
        } else {
            Rectangle().fill(SPAIColor.hairline).frame(height: 1)
        }
    }
}

/// Three dots that breathe while SPAI is thinking.
struct TypingDots: View {
    var color: Color = SPAIColor.secondary

    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1 : 0.55)
                    .opacity(animate ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Workflow presentation

extension SterileStep {
    /// SF Symbol shown for this station across the UI.
    var icon: String {
        switch self {
        case .decontamination: return "bubbles.and.sparkles.fill"
        case .inspection:      return "magnifyingglass"
        case .trayAssembly:    return "tray.full.fill"
        case .packaging:       return "shippingbox.fill"
        case .sealValidation:  return "checkmark.seal.fill"
        }
    }

    /// One-line description used in onboarding and the station picker.
    var summary: String {
        switch self {
        case .decontamination: return "Remove visible soil"
        case .inspection:      return "Check for damage"
        case .trayAssembly:    return "Organize instruments"
        case .packaging:       return "Prepare for sterilization"
        case .sealValidation:  return "Verify packaging integrity"
        }
    }
}
