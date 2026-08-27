//
//  LEDBorder.swift
//  SPAI
//
//  Created by Juan Adams on 6/5/26.
//

import SwiftUI

enum BorderState {
    case normal, warning, critical

    var colors: [Color] {
        switch self {
        case .normal:   return [Color(hex: 0x4A9EFF), Color(hex: 0x9B6BFF), Color(hex: 0x6FD3FF)]
        case .warning:  return [Color(hex: 0xFFB020), Color(hex: 0xFF7A45), Color(hex: 0xFFB020)]
        case .critical: return [Color(hex: 0xFF5A5A), Color(hex: 0xA32D2D), Color(hex: 0xFF5A5A)]
        }
    }
    var secondsPerLoop: Double {
        switch self {
        case .normal: return 6;  case .warning: return 3;  case .critical: return 1.6
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
        )
        .onAppear { spin() }
        .onChange(of: state) { _, _ in spin() }
    }

    private func spin() {
        angle = 0
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
