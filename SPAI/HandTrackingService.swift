//
//  HandTrackingService.swift
//  SPAI
//
//  Tracks both hands and keeps the two wrist menus attached to them.
//
//  The menus behave like a watch face: turn the back of your wrist toward
//  your eyes and the menu rises above it, facing you; turn away and it's
//  gone. Left wrist is the station picker, right wrist is quick actions.
//
//  The service moves the menu entities itself, straight from the tracking
//  loop. Nothing here is published per frame, so SwiftUI is only woken when
//  a menu actually appears or disappears — not 90 times a second.
//

import ARKit
import QuartzCore
import RealityKit
import simd
import SwiftUI

@MainActor
@Observable
final class HandTrackingService {
    enum Side {
        case left, right
    }

    // MARK: Observable state (changes rarely)

    /// True while the left-wrist menu is showing.
    private(set) var isLeftMenuVisible = false
    /// True while the right-wrist menu is showing.
    private(set) var isRightMenuVisible = false
    private(set) var isTracking = false

    // MARK: Internals

    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let worldTracking = WorldTrackingProvider()

    /// Everything tracked for one wrist.
    private final class Wrist {
        weak var panel: Entity?
        /// Half the menu's width and height in metres.
        var panelHalfSize = SIMD2<Float>(0.07, 0.06)
        var filter = AdaptivePointFilter()
        var isShowing = false
        /// When the hand was last seen. A short grace period rides out the
        /// single dropped frames hand tracking produces.
        var lastSeen: TimeInterval = 0
    }

    private let left = Wrist()
    private let right = Wrist()

    /// How long a menu survives its hand going untracked.
    private let lostHandGrace: TimeInterval = 0.25

    // MARK: Setup

    /// Hands a wrist menu's entity to the service to position.
    /// - Parameter panelSize: The menu's width and height in metres.
    func attach(_ panel: Entity?, to side: Side, panelSize: SIMD2<Float>) {
        let wrist = wrist(for: side)
        wrist.panel = panel
        wrist.panelHalfSize = panelSize / 2
        panel?.isEnabled = wrist.isShowing
    }

    /// Simulator / no-hand-tracking fallback: park both menus at fixed spots
    /// in the room and leave them showing.
    func showAtFixedPositions(left leftPosition: SIMD3<Float>, right rightPosition: SIMD3<Float>) {
        left.panel?.position = leftPosition
        right.panel?.position = rightPosition
        setShowing(true, for: .left)
        setShowing(true, for: .right)
    }

    func start() async {
        guard HandTrackingProvider.isSupported else {
            print("[hand-tracking] not supported on this device")
            return
        }

        // Head pose tells us whether a wrist is turned toward the eyes. It is
        // a nice-to-have: if world tracking is unavailable the menus fall
        // back to "back of the wrist facing up".
        var providers: [any DataProvider] = [handTracking]
        if WorldTrackingProvider.isSupported {
            providers.append(worldTracking)
        }

        do {
            try await session.run(providers)
            isTracking = true
            print("[hand-tracking] session started")
            await processUpdates()
        } catch {
            print("[hand-tracking] failed to start: \(error)")
        }
        isTracking = false
        hide(.left)
        hide(.right)
    }

    func stop() {
        session.stop()
    }

    // MARK: Tracking loop

    private func processUpdates() async {
        for await event in handTracking.anchorUpdates {
            let anchor = event.anchor
            let side: Side = anchor.chirality == .left ? .left : .right
            let now = CACurrentMediaTime()

            guard anchor.isTracked, let joints = joints(from: anchor) else {
                handLost(side, at: now)
                continue
            }
            place(side, joints: joints, at: now)
        }
    }

    private func place(_ side: Side, joints: WristJoints, at now: TimeInterval) {
        let wrist = wrist(for: side)
        wrist.lastSeen = now

        guard let placement = WristMenuSolver.placement(
            joints: joints,
            isLeft: side == .left,
            head: headPosition(at: now),
            panelHalfSize: wrist.panelHalfSize
        ) else { return }

        // Filter first, even while hidden, so the speed estimate is current
        // and the menu doesn't appear mid-swing.
        let wasShowing = wrist.isShowing
        let filtered = wrist.filter.update(placement.position, at: now)

        let show = WristMenuSolver.shouldShow(
            facing: placement.facing,
            speed: wrist.filter.speed,
            isShowing: wasShowing
        )

        if show {
            // On the frame it appears, snap to the wrist instead of gliding
            // in from wherever it was last hidden.
            wrist.panel?.setPosition(wasShowing ? filtered : placement.position, relativeTo: nil)
        }
        if show != wasShowing {
            setShowing(show, for: side)
        }
    }

    private func handLost(_ side: Side, at now: TimeInterval) {
        let wrist = wrist(for: side)
        guard wrist.isShowing, now - wrist.lastSeen > lostHandGrace else { return }
        hide(side)
    }

    private func hide(_ side: Side) {
        wrist(for: side).filter.reset()
        setShowing(false, for: side)
    }

    private func setShowing(_ showing: Bool, for side: Side) {
        let wrist = wrist(for: side)
        wrist.isShowing = showing
        wrist.panel?.isEnabled = showing
        switch side {
        case .left:  if isLeftMenuVisible != showing { isLeftMenuVisible = showing }
        case .right: if isRightMenuVisible != showing { isRightMenuVisible = showing }
        }
    }

    private func wrist(for side: Side) -> Wrist {
        side == .left ? left : right
    }

    // MARK: ARKit → plain vectors

    private func joints(from anchor: HandAnchor) -> WristJoints? {
        guard let skeleton = anchor.handSkeleton else { return nil }
        let origin = anchor.originFromAnchorTransform

        func world(_ name: HandSkeleton.JointName) -> SIMD3<Float>? {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { return nil }
            let transform = origin * joint.anchorFromJointTransform
            return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }

        guard let wrist = world(.wrist),
              let index = world(.indexFingerKnuckle),
              let middle = world(.middleFingerKnuckle),
              let little = world(.littleFingerKnuckle) else { return nil }

        return WristJoints(wrist: wrist, indexKnuckle: index, middleKnuckle: middle, littleKnuckle: little)
    }

    private func headPosition(at time: TimeInterval) -> SIMD3<Float>? {
        guard worldTracking.state == .running,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: time),
              device.isTracked else { return nil }
        let transform = device.originFromAnchorTransform
        return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}
