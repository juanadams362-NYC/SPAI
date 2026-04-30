//
//  AppBackground.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.04, green: 0.07, blue: 0.10),
                Color(red: 0.08, green: 0.11, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    AppBackground()
}
