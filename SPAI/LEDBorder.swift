//
//  LEDBorder.swift
//  SPAI
//
//  Created by Juan Adams on 6/5/26.
//


//
//  LEDBorder.swift
//  SPAI
//
//  An animated "LED strip" border. Instead of a static stroke, an angular
//  gradient of accent colors rotates continuously around the panel edge,
//  giving panels a living, AI-active feel. Used on detection / AI panels.
//

import SwiftUI

struct LEDBorder: ViewModifier {
    var cornerRadius: CGFloat = SPAIRadius.medium
    var lineWidth: CGFloat = 2

    // Drives the rotation. Flipped on appear to start the loop.
    @State private var rotation: Double = 0

    // The accent colors the LED sweeps through. Repeating the first color
    // at the end makes the gradient loop seamlessly with no hard seam.
    private var ledColors: [Color] {
        [
            SPAIColor.primary,    // blue
            SPAIColor.secondary,  // purple
            SPAIColor.accent,     // light blue
            SPAIColor.primary     // back to blue — seamless loop
        ]
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: ledColors),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: lineWidth
                    )
                    // Soft glow so the border reads as light, not just a line.
                    .shadow(color: SPAIColor.primary.opacity(0.4), radius: 4)
            }
            .onAppear {
                // Continuously rotate the gradient for the traveling-light effect.
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

extension View {
    /// Adds an animated LED-strip border that sweeps through the accent colors.
    func ledBorder(cornerRadius: CGFloat = SPAIRadius.medium, lineWidth: CGFloat = 2) -> some View {
        modifier(LEDBorder(cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

#Preview {
    VStack(spacing: 40) {
        Text("AI Detection Active")
            .foregroundStyle(.white)
            .padding(40)
            .background(SPAIColor.neutralDark, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
            .ledBorder()
    }
    .padding(60)
    .background(.black)
}