//
//  DetectionAlertCard.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct DetectionAlertCard: View {
    let title: String
    let message: String
    let status: DetectionStatus
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text(status.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.35))
                    .clipShape(Capsule())
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: confidence)
                    .tint(status.color)

                Text("Confidence: \(Int(confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
        .background(.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
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
    .background(.black)
}
