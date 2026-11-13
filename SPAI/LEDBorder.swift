//
//  LEDBorder.swift
//  SPAI
//
//  Created by Juan Adams on 6/5/26.
//

import SwiftUI

enum BorderState {
    /// Nothing to report. A still, quiet outline.
    case normal
    /// The guide is pointing at this panel.
    case attention
    case warning
    case critical

    var colors: [Color] {
        switch self {
        // Paper-and-stone neutrals, matching the hairlines on the website.
        case .normal:    return [Color(hex: 0xF2EFE9), Color(hex: 0x8A847B), Color(hex: 0xBDB7AD)]
        case .attention: return [Color(hex: 0x6FD3FF), Color(hex: 0xFFFFFF), Color(hex: 0x4A9EFF)]
        case .warning:   return [Color(hex: 0xFFB020), Color(hex: 0xFF7A45), Color(hex: 0xFFB020)]
        case .critical:  return [Color(hex: 0xFF5A5A), Color(hex: 0xA32D2D), Color(hex: 0xFF5A5A)]
        }
    }

    /// Only states that need the user's eye are allowed to move.
    ///
    /// Every panel used to run a spinning gradient all the time. With a dozen
    /// panels in view that is a dozen things moving in peripheral vision, and
    /// motion that means nothing trains people to ignore motion that does.
    /// Now a moving border always means "look here".
    var isAnimated: Bool { self != .normal }

    var secondsPerLoop: Double {
        switch self {
        case .normal:    return 6
        case .attention: return 2.4
        case .warning:   return 3
        case .critical:  return 1.6
        }
    }

    /// How strongly the outline is drawn.
    var strength: Double {
        self == .normal ? 0.55 : 1
    }

    /// Soft glow behind the outline, for states that should stand out.
    var glowRadius: CGFloat {
        switch self {
        case .normal:    return 0
        case .attention: return 14
        case .warning:   return 8
        case .critical:  return 12
        }
    }
}

struct LEDBorder: ViewModifier {
    var state: BorderState = .normal
    var cornerRadius: CGFloat = 22
    var lineWidth: CGFloat = 2

    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: state.colors + [state.colors.first!]),
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: lineWidth
                )
                .opacity(state.strength)
                .shadow(color: state.colors[0].opacity(state.glowRadius > 0 ? 0.7 : 0),
                        radius: state.glowRadius)
                .allowsHitTesting(false)
        )
        .onAppear { restart() }
        .onChange(of: state) { _, _ in restart() }
    }

    private func restart() {
        // Stop whatever loop is running by snapping back without animation.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { angle = 0 }

        guard state.isAnimated else { return }
        withAnimation(.linear(duration: state.secondsPerLoop).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

extension View {
    func ledBorder(_ state: BorderState = .normal, cornerRadius: CGFloat = 22, lineWidth: CGFloat = 2) -> some View {
        modifier(LEDBorder(state: state, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF)/255,
                  green: Double((hex >> 8) & 0xFF)/255,
                  blue: Double(hex & 0xFF)/255, opacity: 1)
    }
}
