//
//  FeatureCard.swift
//  SPAI
//

import SwiftUI

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = SPAIColor.primary
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: tint.opacity(0.35), radius: 12)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SPAIColor.textPrimary)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(SPAIColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(SPAIColor.surface)
                // A faint wash of the card's color in the top corner.
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.16), tint.opacity(0)],
                            center: .topLeading, startRadius: 0, endRadius: 220
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FeatureCard(
        title: "AI Detection",
        subtitle: "Gloves, bare hands and instruments, live",
        icon: "viewfinder",
        tint: SPAIColor.secondary,
        footnote: "Cloud + on-device"
    )
    .frame(width: 280)
    .padding()
    .background(SPAIColor.neutralDark)
}
