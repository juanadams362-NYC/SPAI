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
        SPAIChip(text: text, icon: systemImage, tint: color)
    }
}

#Preview {
    StatusPill(text: "Prototype", systemImage: "sparkles", color: SPAIColor.secondary)
        .padding()
        .background(.black)
}
