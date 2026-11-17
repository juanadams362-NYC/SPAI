//
//  AppBackground.swift
//  SPAI
//
//  Smoked-ink wash with slowly drifting aurora glows. Sits on top of the window's
//  native glass (see `spaiWindowBackground`) so the room still reads through.
//

import SwiftUI

struct AppBackground: View {
    var showsAurora: Bool = true

    @State private var drift = false

    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0x0C1A2B), Color(hex: 0x060C17)],
            startPoint: .top, endPoint: .bottom
        )
        .opacity(0.82)
        .overlay {
            if showsAurora {
                ZStack {
                    glow(SPAIColor.primary, opacity: 0.30, size: 760)
                        .offset(x: drift ? -300 : -360, y: drift ? -250 : -200)
                    glow(SPAIColor.secondaryDeep, opacity: 0.30, size: 700)
                        .offset(x: drift ? 380 : 320, y: drift ? 230 : 290)
                    glow(SPAIColor.teal, opacity: 0.14, size: 520)
                        .offset(x: drift ? 300 : 360, y: drift ? -260 : -220)
                }
            }
        }
        .overlay {
            // Hairline grid — a quiet "sterile field" texture.
            GridPattern(spacing: 44)
                .stroke(Color.white.opacity(0.035), lineWidth: 1)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard showsAurora else { return }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func glow(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

/// Evenly spaced horizontal and vertical lines.
struct GridPattern: Shape {
    var spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0 else { return path }
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

#Preview {
    AppBackground()
        .frame(width: 1000, height: 660)
}
