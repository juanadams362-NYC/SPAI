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
    @State private var detectionService = DetectionService()   // shared everywhere now

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
        }
        .windowStyle(.plain)

        WindowGroup(id: "settings") {
            SettingsView()
                .environment(appModel)
                .environment(detectionService)
        }
        .windowStyle(.plain)

        // Sim-only upload window. PhotosPicker presents a sheet, which can't
        // appear inside an ImmersiveSpace — so the picker lives here.
        WindowGroup(id: "upload") {
            UploadWindowView()
                .environment(appModel)
                .environment(detectionService)
        }
        .windowStyle(.plain)
        .defaultSize(width: 520, height: 640)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .environment(detectionService)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
