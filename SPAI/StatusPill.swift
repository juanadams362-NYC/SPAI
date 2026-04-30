//
//  StatusPill.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct StatusPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(color.opacity(0.28))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

#Preview {
    StatusPill(text: "Prototype", systemImage: "sparkles", color: .blue)
        .padding()
        .background(.black)
}
