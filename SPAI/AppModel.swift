//
//  AppModel.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

/// Maintains app-wide state shared across the window and the immersive space.
@MainActor
@Observable
class AppModel {
    // Single source of truth for the immersive space id.
    // Must match the id declared in SPAIApp's ImmersiveSpace scene.
    let immersiveSpaceID = "SPAIImmersiveSpace"

    // Tracks where we are in the open/close lifecycle so we can guard
    // against double-taps during the transition animation.
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
}
