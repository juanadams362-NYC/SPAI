//
//  DetectionAlertCard.swift
//  SPAI
//

import SwiftUI

struct DetectionAlertCard: View {
    let title: String
    let message: String
    let status: DetectionStatus
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s + 4) {
            HStack(spacing: 12) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(SPAIColor.neutralDark)

                Spacer()

                Text(status.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(status.color)
                    .clipShape(Capsule())
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(SPAIColor.neutralDark.opacity(0.65))

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: confidence)
                    .tint(status.color)

                Text("Confidence: \(Int(confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(SPAIColor.neutralDark.opacity(0.5))
            }
        }
        .padding(SPAISpacing.m)
        .background(.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium)
                .stroke(.white.opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

#Preview {
    DetectionAlertCard(
        title: "Glove Detection",
        message: "Gloves detected. PPE check is currently passing.",
        status: .safe,
        confidence: 0.94
    )
    .padding()
    .background(SPAIColor.neutralLight)
}
