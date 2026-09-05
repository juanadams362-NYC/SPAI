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
    /// Starts at full passthrough. This is an app for handling real instruments on a real
    /// bench — the workspace belongs over the room, not instead of it.
    @State private var immersionStyle: ImmersionStyle = .mixed

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
        // All three styles, not just .progressive.
        //
        // SCRUM-117 set this to `in: .progressive` alone. Bare `.progressive` leaves
        // ProgressiveImmersionStyle.minimumImmersionAmount nil, so the Digital Crown is clamped
        // to the system's default floor and can never reach 0 — dialling all the way down still
        // left you part-immersed, and pushing up snapped to full. That is the "only goes halfway
        // out" behaviour, and it is why the environment got pulled.
        //
        // Offering .mixed and .full alongside it lets the crown travel the whole way: out to
        // .mixed for unobstructed passthrough, in to .full when someone wants the room gone.
        .immersionStyle(selection: $immersionStyle, in: .mixed, .progressive, .full)
    }
}

/// Root of the "home" window: chooses between the welcome pages and the home screen.
///
/// Deliberately does **not** tear the immersive space down on its own scene phase. Entering the
/// workflow dismisses this very window, which sends this scene to `.background` while the app is
/// perfectly alive — so a teardown here fires the instant the user enters, killing the space they
/// just opened. Scene phase on a dismissable window is not an app lifecycle signal.
///
/// `ImmersiveView` owns that teardown instead, which is correct: it is the scene that actually
/// holds the immersive content, and it only backgrounds when the app really does.
private struct RootSceneView: View {
    @Environment(AppModel.self) private var appModel

    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false

    var body: some View {
        Group {
            if alwaysShowOnboarding || !appModel.hasCompletedOnboarding {
                OnboardingView()
            } else {
                HomeView()
            }
        }
    }
}
