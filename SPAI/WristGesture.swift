//
//  WristGesture.swift
//  SPAI
//

import simd

/// Decides whether a wrist is being *presented* to the user — held in the posture you'd
/// naturally adopt to read something off your forearm.
///
/// Both wrist menus used to appear whenever the hand was tracked at all, which is most of the
/// time you are working, so they were permanently in the way. The gesture gate means the menu
/// is there when you ask for it and gone otherwise.
///
/// The shared signal for both wrists is simple and robust: the face of the panel — the wrist's
/// local up axis — is turned toward the user's head. That is exactly what your forearm does
/// when you check a watch, and what it does when you hold something flat on your inner forearm
/// to read it. What separates the two poses is the forearm's own attitude:
///
/// - **Right, "checking the time":** forearm raised and rotated across the body. The panel
///   rides beside the wrist. No constraint on forearm pitch — people check a watch at all
///   sorts of angles.
/// - **Left, "book on the forearm":** forearm held roughly level, as if a book were resting
///   along it. Requiring level-ness is what stops the left panel appearing every time the arm
///   happens to swing past the right rotation.
enum WristGesture {

    /// Facing dot product at which a wrist starts counting as presented.
    ///
    /// Deliberately different from `exitThreshold`: a single threshold makes the panel strobe
    /// while the user holds their arm right at the boundary, which is worse than either state.
    static let enterThreshold: Float = 0.55

    /// Facing dot product below which a presented wrist stops counting. The gap between this
    /// and `enterThreshold` is the hysteresis band.
    static let exitThreshold: Float = 0.30

    /// How level the left forearm must be. 0.6 allows a comfortable tilt in either direction
    /// while still rejecting an arm hanging down or raised overhead.
    static let levelTolerance: Float = 0.6

    /// How much the wrist's face is turned toward the head, from -1 (away) to 1 (straight at).
    static func facing(
        pose: (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>),
        headPosition: SIMD3<Float>
    ) -> Float {
        let toHead = headPosition - pose.position
        let distance = length(toHead)
        // Degenerate case: head and wrist coincident. Not a real pose; treat as not facing.
        guard distance > 0.0001 else { return -1 }
        return dot(toHead / distance, pose.up)
    }

    /// Whether the forearm is held roughly level with the floor.
    static func isForearmLevel(
        pose: (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)
    ) -> Bool {
        // `forward` runs along the arm, so its vertical component is the arm's pitch.
        abs(pose.forward.y) < levelTolerance
    }

    /// Applies the gesture test with hysteresis.
    ///
    /// - Parameters:
    ///   - wasPresented: the previous result, which sets which threshold applies.
    ///   - requireLevelForearm: true for the left "book" pose, false for the right "watch" pose.
    static func isPresented(
        pose: (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>)?,
        headPosition: SIMD3<Float>?,
        wasPresented: Bool,
        requireLevelForearm: Bool
    ) -> Bool {
        // No hand, no menu.
        guard let pose else { return false }

        // Without a head fix there is nothing to face, so fall back to "tracked means shown"
        // rather than hiding a menu the user cannot summon.
        guard let headPosition else { return true }

        if requireLevelForearm, !isForearmLevel(pose: pose) {
            return false
        }

        let f = facing(pose: pose, headPosition: headPosition)
        return wasPresented ? f > exitThreshold : f > enterThreshold
    }
}
