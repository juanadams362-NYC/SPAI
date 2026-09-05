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

    var body: some Scene {
        WindowGroup(id: "home") {
            RootSceneView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 800, height: 600)

        // `Window`, not `WindowGroup`: a WindowGroup is multi-instance by design, so every
        // openWindow(id: "settings") minted another copy and none of them replaced the last.
        // A Window is a singleton scene — openWindow on an already-open one just brings it
        // forward, which makes the spam impossible regardless of how the callers behave.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 450, height: 700)
        .windowResizability(.contentSize)

        Window("Upload", id: "upload") {
            UploadWindowView()
                .environment(appModel)
                .environment(detectionService)
                .environment(continuityCamera)
        }
        .windowStyle(.plain)
        .defaultSize(width: 520, height: 640)
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

/// Root of the "home" window. Owns the onboarding-vs-home decision and, more importantly,
/// the scene-phase teardown: an ImmersiveSpace is a separate scene from this window, so
/// closing the app leaves its content floating in the room unless something explicitly
/// dismisses it. Nothing did, which is why immersive content outlived the app during testing.
private struct RootSceneView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false

    var body: some View {
        Group {
            if alwaysShowOnboarding || !appModel.hasCompletedOnboarding {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            teardown()
        }
    }

    private func teardown() {
        // Auxiliary windows are singletons now, but they still need dismissing —
        // a Window that is never closed reopens with the app on next launch.
        if appModel.isSettingsWindowOpen {
            dismissWindow(id: "settings")
            appModel.isSettingsWindowOpen = false
        }
        if appModel.isUploadWindowOpen {
            dismissWindow(id: "upload")
            appModel.isUploadWindowOpen = false
        }

        guard appModel.immersiveSpaceState != .closed else { return }
        Task { @MainActor in
            await dismissImmersiveSpace()
            appModel.immersiveSpaceState = .closed
        }
    }
}
