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
    @State private var immersionStyle: ImmersionStyle = .progressive

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
        .defaultSize(width: 1040, height: 720)

        WindowGroup(id: "settings") {
            SettingsView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 440, height: 760)
        .windowResizability(.contentSize)

        WindowGroup(id: "upload") {
            UploadWindowView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 520, height: 700)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .immersionStyle(selection: $immersionStyle, in: .progressive)
    }
}
