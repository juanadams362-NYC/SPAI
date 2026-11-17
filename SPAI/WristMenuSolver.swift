//
//  WristMenuSolver.swift
//  SPAI
//
//  The geometry behind the wrist menus: where a menu floats relative to the
//  wrist, when it should be showing, and how its motion is smoothed.
//
//  Everything here is plain vector math with no ARKit or RealityKit types, so
//  it can be unit-tested and reasoned about without a headset.
//

import Foundation
import simd

/// The four hand joints the wrist menus are placed from, in world space.
struct WristJoints {
    var wrist: SIMD3<Float>
    var indexKnuckle: SIMD3<Float>
    var middleKnuckle: SIMD3<Float>
    var littleKnuckle: SIMD3<Float>
}

enum WristMenuSolver {
    // MARK: Tuning

    /// A watch sits on the forearm side of the wrist joint, not on the joint.
    static let watchSetback: Float = 0.035
    /// How far the menu floats off the skin, toward the eyes.
    static let lift: Float = 0.05
    /// Half the width of a forearm, plus a little air. The menu's nearest
    /// edge is kept at least this far from the arm's centre line.
    static let armClearance: Float = 0.05

    /// The menu appears once the back of the wrist is turned this far toward
    /// the eyes (cosine of the angle: 0.35 ≈ within 70°)…
    static let showFacing: Float = 0.35
    /// …and stays until it has clearly turned away. The gap between the two
    /// stops the menu flickering at the edge of the gesture.
    static let hideFacing: Float = 0.12

    /// Above this hand speed the menu hides — it can't be read while the arm
    /// is swinging, and hiding it is what stops it trailing into the arm.
    static let hideSpeed: Float = 1.6
    /// It comes back once the hand has settled below this speed (m/s).
    static let showSpeed: Float = 0.9

    struct Placement {
        /// World-space centre of the menu.
        var position: SIMD3<Float>
        /// How squarely the back of the wrist faces the viewer, -1…1.
        var facing: Float
    }

    // MARK: Geometry

    /// Unit vector pointing out of the back of the hand.
    ///
    /// Built from joint *positions* rather than the wrist joint's own axes.
    /// Positions mean the same thing on both hands; the joint axes are
    /// mirrored between left and right, which is how a menu ends up on the
    /// wrong side of the arm.
    static func backOfHandNormal(_ joints: WristJoints, isLeft: Bool) -> SIMD3<Float>? {
        guard let toFingers = unit(joints.middleKnuckle - joints.wrist),
              let acrossKnuckles = unit(joints.indexKnuckle - joints.littleKnuckle) else { return nil }
        // Right hand, palm down, fingers forward: index is on the left, and
        // fingers × across points up out of the back of the hand. The left
        // hand is the mirror image, so the operands swap.
        let normal = isLeft ? cross(acrossKnuckles, toFingers) : cross(toFingers, acrossKnuckles)
        return unit(normal)
    }

    /// Where the wrist menu belongs for this hand pose.
    ///
    /// The menu faces the viewer and sits *beside* the arm as the viewer sees
    /// it: lifted off the watch position toward the eyes, then slid sideways —
    /// perpendicular to the arm's line in the view — until its nearest edge
    /// clears the arm. In the usual watch-glance pose, with the forearm
    /// lying across the view, "sideways" is straight up, so the menu rises
    /// above the wrist.
    ///
    /// Because the offset is always perpendicular to the arm and at least the
    /// menu's own half-size plus an arm's width, the arm cannot cross the
    /// menu, whatever angle the wrist is held at.
    ///
    /// - Parameters:
    ///   - head: The viewer's head position, if known. Without it the menu
    ///     falls back to treating "back of the wrist facing up" as the gesture.
    ///   - panelHalfSize: Half the menu's width and height, in metres.
    static func placement(
        joints: WristJoints,
        isLeft: Bool,
        head: SIMD3<Float>?,
        panelHalfSize: SIMD2<Float>
    ) -> Placement? {
        guard let normal = backOfHandNormal(joints, isLeft: isLeft),
              let toFingers = unit(joints.middleKnuckle - joints.wrist) else { return nil }

        let watch = joints.wrist - toFingers * watchSetback
        let worldUp = SIMD3<Float>(0, 1, 0)

        let toHead: SIMD3<Float>
        let facing: Float
        if let head, let direction = unit(head - watch) {
            toHead = direction
            facing = dot(normal, direction)
        } else {
            toHead = normal
            facing = normal.y
        }

        // The menu is billboarded, so its on-screen "up" is world up with the
        // view direction removed. Nil when looking straight down at the wrist.
        let viewUp = unit(worldUp - toHead * dot(worldUp, toHead))

        // The arm's direction as it appears in the view, and the in-view
        // direction perpendicular to it — the way to slide clear of the arm.
        let away: SIMD3<Float>
        if let armInView = unit(toFingers - toHead * dot(toFingers, toHead)) {
            var perpendicular = cross(toHead, armInView)
            // Two perpendiculars to choose from: prefer the upper side.
            if dot(perpendicular, viewUp ?? normal) < 0 { perpendicular = -perpendicular }
            away = perpendicular
        } else {
            // The arm points straight at the eyes and has no direction in the
            // view; any side is clear of it, so go up.
            away = viewUp ?? normal
        }

        // How far the menu's rectangle extends back toward the arm along
        // that direction.
        let reach: Float
        if let viewUp {
            let viewRight = cross(viewUp, toHead)
            reach = abs(dot(away, viewRight)) * panelHalfSize.x + abs(dot(away, viewUp)) * panelHalfSize.y
        } else {
            reach = max(panelHalfSize.x, panelHalfSize.y)
        }

        let position = watch + toHead * lift + away * (reach + armClearance)
        return Placement(position: position, facing: facing)
    }

    /// Whether the menu should be showing, given whether it is showing now.
    static func shouldShow(facing: Float, speed: Float, isShowing: Bool) -> Bool {
        if isShowing {
            return facing > hideFacing && speed < hideSpeed
        }
        return facing > showFacing && speed < showSpeed
    }

    private static func unit(_ v: SIMD3<Float>) -> SIMD3<Float>? {
        let len = length(v)
        guard len.isFinite, len > 1e-5 else { return nil }
        return v / len
    }
}

// MARK: - Smoothing

/// A speed-adaptive low-pass filter (the "1€ filter") for a 3D point.
///
/// A fixed amount of smoothing forces a bad trade: enough to hide hand-
/// tracking jitter at rest makes the menu lag centimetres behind a moving
/// wrist — far enough to end up inside the arm. This filter smooths heavily
/// when the hand is still and barely at all when it moves, so the menu is
/// steady to read and still keeps up.
struct AdaptivePointFilter {
    /// Cutoff (Hz) at rest. Lower = steadier when still.
    var minCutoff: Float = 1.2
    /// How quickly the cutoff opens up with speed. Higher = less lag in motion.
    var beta: Float = 14
    /// Cutoff (Hz) for the speed estimate itself.
    var speedCutoff: Float = 1.5

    private(set) var value: SIMD3<Float>?
    /// Smoothed speed of the raw input, metres per second.
    private(set) var speed: Float = 0

    private var lastRaw: SIMD3<Float>?
    private var lastTime: TimeInterval?

    mutating func reset() {
        value = nil
        lastRaw = nil
        lastTime = nil
        speed = 0
    }

    /// Feeds one raw sample in and returns the filtered point.
    @discardableResult
    mutating func update(_ raw: SIMD3<Float>, at time: TimeInterval) -> SIMD3<Float> {
        guard let previous = value, let lastRaw, let lastTime else {
            value = raw
            self.lastRaw = raw
            self.lastTime = time
            return raw
        }

        // Guard against duplicate or out-of-order timestamps.
        let dt = Float(max(time - lastTime, 1.0 / 240.0))
        let rawSpeed = length(raw - lastRaw) / dt
        speed += (rawSpeed - speed) * Self.alpha(cutoff: speedCutoff, dt: dt)

        let cutoff = minCutoff + beta * speed
        let filtered = previous + (raw - previous) * Self.alpha(cutoff: cutoff, dt: dt)

        value = filtered
        self.lastRaw = raw
        self.lastTime = time
        return filtered
    }

    private static func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
