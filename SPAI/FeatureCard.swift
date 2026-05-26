//
//  FeatureCard.swift
//  SPAI
//

import SwiftUI

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: SPAIRadius.small)
                    .fill(SPAIColor.primary.opacity(0.2))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SPAIColor.accent)
            }

            VStack(alignment: .leading, spacing: SPAISpacing.xs + 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .padding(SPAISpacing.l)
        .spaiGlass(.dark)
    }
}

#Preview {
    FeatureCard(
        title: "AI Detection",
        subtitle: "PPE, tools, hands, and risk alerts",
        icon: "viewfinder"
    )
    .padding()
    .background(SPAIColor.neutralDark)
}
