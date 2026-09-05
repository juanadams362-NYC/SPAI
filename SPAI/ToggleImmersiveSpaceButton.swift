//
//  ToggleImmersiveSpaceButton.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct ToggleImmersiveSpaceButton: View {

    @Environment(AppModel.self) private var appModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                    case .open:
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        // Close the state here rather than leaving it to ImmersiveView's
                        // onDisappear. If the space is already gone (torn down by a scene
                        // phase change, say) onDisappear never fires again, and the button
                        // would stay disabled in .inTransition forever.
                        appModel.immersiveSpaceState = .closed

                    case .closed:
                        appModel.immersiveSpaceState = .inTransition
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                appModel.immersiveSpaceState = .open

                            case .userCancelled, .error:
                                fallthrough
                            @unknown default:
                                appModel.immersiveSpaceState = .closed
                        }

                    case .inTransition:
                        break
                }
            }
        } label: {
            Text(appModel.immersiveSpaceState == .open ? "Hide Immersive Space" : "Show Immersive Space")
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
        .accessibilityLabel(appModel.immersiveSpaceState == .open ? "Hide immersive space" : "Show immersive space")
        .accessibilityHint(appModel.immersiveSpaceState == .open
            ? "Closes the spatial workspace and its panels"
            : "Opens the spatial workspace with passthrough")
    }
}
