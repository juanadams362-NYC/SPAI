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
    @State private var detectionService = DetectionService()
    @State private var continuityCamera = ContinuityCameraService()

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
            .environment(detectionService)
            .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 800, height: 600)

        WindowGroup(id: "settings") {
            SettingsView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 450, height: 700)

        WindowGroup(id: "upload") {
            UploadWindowView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 520, height: 640)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
