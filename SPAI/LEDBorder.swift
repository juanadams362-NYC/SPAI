//
//  LEDBorder.swift
//  SPAI
//
//  Created by Juan Adams on 6/5/26.
//
//  The light on a panel's edge. Only states that need the user's eye are allowed to move:
//  with a dozen panels in view, motion that means nothing trains people to ignore motion
//  that does. So a calm panel has a still, quiet glass edge; when Pip points at a panel
//  the edge sweeps in bright cyan; a warning sweeps amber; contamination races in rose
//  with a breathing glow.
//

import SwiftUI

enum BorderState {
    /// Nothing to report. A still, quiet edge.
    case normal
    /// The guide is pointing at this panel.
    case attention
    case warning
    case critical

    var isAnimated: Bool { self != .normal }

    /// The bright segment that sweeps around the edge.
    var sweepColors: [Color] {
        switch self {
        case .normal:    return [SPAIColor.primaryBright, SPAIColor.secondary]
        case .attention: return [Color.white, SPAIColor.primaryBright]
        case .warning:   return [Color(hex: 0xFDE68A), SPAIColor.warning]
        case .critical:  return [Color(hex: 0xFECDD3), SPAIColor.critical]
        }
    }

    /// The resting edge between sweeps.
    var restColor: Color {
        switch self {
        case .normal:    return Color.white.opacity(0.12)
        case .attention: return SPAIColor.primaryBright.opacity(0.55)
        case .warning:   return SPAIColor.warning.opacity(0.45)
        case .critical:  return SPAIColor.critical.opacity(0.6)
        }
    }

    var glowColor: Color {
        switch self {
        case .normal:    return .clear
        case .attention: return SPAIColor.primaryBright
        case .warning:   return SPAIColor.warning
        case .critical:  return SPAIColor.critical
        }
    }

    var secondsPerLoop: Double {
        switch self {
        case .normal:    return 6
        case .attention: return 2.4
        case .warning:   return 3
        case .critical:  return 1.6
        }
    }
}

struct LEDBorder: ViewModifier {
    var state: BorderState = .normal
    var cornerRadius: CGFloat = 22
    var lineWidth: CGFloat = 2

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                // A fresh ring per state restarts its animations cleanly.
                LEDRing(state: state, cornerRadius: cornerRadius, lineWidth: lineWidth)
                    .id(state)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: state)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct LEDRing: View {
    let state: BorderState
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    @State private var rotation: Double = 0
    @State private var breathing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if state.isAnimated {
                shape.strokeBorder(state.restColor, lineWidth: lineWidth)

                GeometryReader { proxy in
                    // A square big enough to cover the panel at any rotation.
                    let side = (proxy.size.width * proxy.size.width + proxy.size.height * proxy.size.height).squareRoot()
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: Color.clear, location: 0.55),
                            .init(color: state.sweepColors[0], location: 0.78),
                            .init(color: state.sweepColors[1], location: 0.9),
                            .init(color: Color.clear, location: 1.0)
                        ]),
                        center: .center,
                        angle: .zero
                    )
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(rotation))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .mask { shape.strokeBorder(lineWidth: lineWidth) }
            } else {
                // Still glass edge: light catching the top-leading corner.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [SPAIColor.primaryBright.opacity(0.4), Color.white.opacity(0.1), SPAIColor.secondary.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
            }
        }
        .shadow(color: state.glowColor.opacity(breathing ? 0.75 : 0.3), radius: breathing ? 16 : 8)
        .onAppear {
            guard state.isAnimated else { return }
            withAnimation(.linear(duration: state.secondsPerLoop).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

extension View {
    func ledBorder(_ state: BorderState = .normal, cornerRadius: CGFloat = 22, lineWidth: CGFloat = 2) -> some View {
        modifier(LEDBorder(state: state, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}
