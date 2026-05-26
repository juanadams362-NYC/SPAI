//
//  AppBackground.swift
//  SPAI
//

import SwiftUI

struct AppBackground: View {
    var body: some View {
        ZStack {
            SPAIColor.neutralDark
                .ignoresSafeArea()

            RadialGradient(
                colors: [SPAIColor.primary.opacity(0.18), Color.clear],
                center: .topLeading,
                startRadius: 50,
                endRadius: 900
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [SPAIColor.accent.opacity(0.10), Color.clear],
                center: .bottomTrailing,
                startRadius: 80,
                endRadius: 800
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    AppBackground()
}
