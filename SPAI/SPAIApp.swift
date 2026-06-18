//
//  SPAIApp.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

@main
struct SPAIApp: App {
    @State private var appModel = AppModel()

    // Testing toggle: when on, onboarding shows every launch.
    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false

    var body: some Scene {
        WindowGroup(id: "home") {
            Group {
                if alwaysShowOnboarding || !appModel.hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    HomeView()
                }
            }
            .environment(appModel)
        }
        .windowStyle(.plain)

        WindowGroup(id: "settings") {
            SettingsView()
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
