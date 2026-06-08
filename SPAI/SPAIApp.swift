//
//  SPAIApp.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

@main
struct SPAIApp: App {
    // One shared AppModel for the whole app, injected into every scene.
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: "home") {
            // First launch shows the walkthrough; after it's completed,
            // the app goes to the home screen. Same window, swapped content.
            Group {
                if appModel.hasCompletedOnboarding {
                    HomeView()
                } else {
                    OnboardingView()
                }
            }
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
