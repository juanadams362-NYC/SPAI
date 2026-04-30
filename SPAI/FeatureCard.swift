//
//  FeatureCard.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(22)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

#Preview {
    FeatureCard(
        title: "AI Detection",
        subtitle: "PPE, tools, hands, and risk alerts",
        icon: "viewfinder"
    )
    .padding()
    .background(.black)
}
