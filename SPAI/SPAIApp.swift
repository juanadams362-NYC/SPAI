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
        WindowGroup {
            HomeView()
                .environment(appModel)
        }

        // Uses AppModel's id constant so the scene and the open call
        // can never drift out of sync.
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
    }
}
