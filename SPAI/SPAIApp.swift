//
//  SPAIApp.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

@main
struct SPNAIApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }

        ImmersiveSpace(id: "SPNAIImmersiveSpace") {
            ImmersiveView()
        }
    }
}
