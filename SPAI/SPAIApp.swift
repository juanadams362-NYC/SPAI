//
//  SPAIApp.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

@main
struct SPAIApp: App {
    // One shared AppModel for the whole app, injected into every scene
    // so the window and the immersive space read the same state.
    @State private var appModel = AppModel()

    var body: some Scene {
        // Giving the window an explicit id lets us dismiss it by name
        // when the user enters the immersive workflow.
        WindowGroup(id: "home") {
            HomeView()
                .environment(appModel)
        }
        .windowStyle(.plain)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
