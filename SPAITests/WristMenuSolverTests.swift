//
//  WristMenuSolverTests.swift
//  SPAITests
//
//  The wrist menus must sit on the back of the wrist, face the user, and
//  never cross the arm.
//

import XCTest
import simd
@testable import SPAI

@MainActor
final class WristMenuSolverTests: XCTestCase {

    private let head = SIMD3<Float>(0, 1.6, 0)
    private let panelHalfSize = SIMD2<Float>(0.078, 0.065)

    /// Builds hand joints from a wrist position, the direction the fingers
    /// point, and the direction the back of the hand faces.
    private func hand(
        wrist: SIMD3<Float>,
        fingers: SIMD3<Float>,
        backOfHand: SIMD3<Float>,
        isLeft: Bool
    ) -> WristJoints {
        let d = normalize(fingers)
        let n = normalize(backOfHand)
        // Direction from the little-finger knuckle to the index knuckle.
        let across = isLeft ? cross(d, n) : cross(n, d)
        let middle = wrist + d * 0.09
        return WristJoints(
            wrist: wrist,
            indexKnuckle: middle + across * 0.02,
            middleKnuckle: middle,
            littleKnuckle: middle - across * 0.03
        )
    }

    // MARK: - Which way is the back of the hand

    func testBackOfHandNormalPointsUpForPalmDownHands() throws {
        for isLeft in [false, true] {
            let joints = hand(wrist: [0, 1, -0.4], fingers: [0, 0, -1], backOfHand: [0, 1, 0], isLeft: isLeft)
            let normal = try XCTUnwrap(WristMenuSolver.backOfHandNormal(joints, isLeft: isLeft))
            XCTAssertEqual(normal.y, 1, accuracy: 0.001, isLeft ? "left" : "right")
        }
    }

    func testNormalFlipsWhenTheHandTurnsOver() throws {
        let joints = hand(wrist: [0, 1, -0.4], fingers: [0, 0, -1], backOfHand: [0, -1, 0], isLeft: false)
        let normal = try XCTUnwrap(WristMenuSolver.backOfHandNormal(joints, isLeft: false))
        XCTAssertEqual(normal.y, -1, accuracy: 0.001)
    }

    func testDegenerateJointsProduceNoPlacement() {
        let collapsed = WristJoints(wrist: .zero, indexKnuckle: .zero, middleKnuckle: .zero, littleKnuckle: .zero)
        XCTAssertNil(WristMenuSolver.placement(joints: collapsed, isLeft: true, head: head, panelHalfSize: panelHalfSize))
    }

    // MARK: - Watch gesture

    func testWristTurnedTowardTheEyesFacesTheViewer() throws {
        let wrist = SIMD3<Float>(-0.15, 1.2, -0.35)
        let joints = hand(wrist: wrist, fingers: [1, 0, 0], backOfHand: normalize(head - wrist), isLeft: true)
        let placement = try XCTUnwrap(
            WristMenuSolver.placement(joints: joints, isLeft: true, head: head, panelHalfSize: panelHalfSize)
        )
        XCTAssertGreaterThan(placement.facing, 0.9)
        XCTAssertTrue(WristMenuSolver.shouldShow(facing: placement.facing, speed: 0, isShowing: false))
    }

    func testWristTurnedAwayIsHidden() throws {
        let wrist = SIMD3<Float>(-0.15, 1.2, -0.35)
        let joints = hand(wrist: wrist, fingers: [1, 0, 0], backOfHand: normalize(wrist - head), isLeft: true)
        let placement = try XCTUnwrap(
            WristMenuSolver.placement(joints: joints, isLeft: true, head: head, panelHalfSize: panelHalfSize)
        )
        XCTAssertLessThan(placement.facing, 0)
        XCTAssertFalse(WristMenuSolver.shouldShow(facing: placement.facing, speed: 0, isShowing: true))
    }

    func testShowingHasHysteresis() {
        // Between the two thresholds: stays as it was.
        let between = (WristMenuSolver.showFacing + WristMenuSolver.hideFacing) / 2
        XCTAssertFalse(WristMenuSolver.shouldShow(facing: between, speed: 0, isShowing: false))
        XCTAssertTrue(WristMenuSolver.shouldShow(facing: between, speed: 0, isShowing: true))
    }

    func testFastHandHidesTheMenu() {
        XCTAssertFalse(WristMenuSolver.shouldShow(facing: 1, speed: 2.5, isShowing: true))
        XCTAssertFalse(WristMenuSolver.shouldShow(facing: 1, speed: 1.2, isShowing: false))
        XCTAssertTrue(WristMenuSolver.shouldShow(facing: 1, speed: 1.2, isShowing: true))
    }

    // MARK: - Never through the arm

    /// As seen from the head, the arm's centre line must stay outside the
    /// menu's rectangle for every wrist angle that shows the menu.
    func testMenuNeverOverlapsTheArm() throws {
        var generator = SystemRandomNumberGenerator()
        func randomUnit() -> SIMD3<Float> {
            while true {
                let v = SIMD3<Float>(
                    Float.random(in: -1...1, using: &generator),
                    Float.random(in: -1...1, using: &generator),
                    Float.random(in: -1...1, using: &generator)
                )
                let len = length(v)
                if len > 0.1 && len <= 1 { return v / len }
            }
        }

        var checked = 0
        for _ in 0..<4000 {
            let isLeft = Bool.random(using: &generator)
            let wrist = SIMD3<Float>(
                Float.random(in: -0.35...0.35, using: &generator),
                Float.random(in: 0.9...1.5, using: &generator),
                Float.random(in: -0.55 ... -0.2, using: &generator)
            )
            let fingers = randomUnit()
            let back = cross(fingers, randomUnit())
            guard length(back) > 0.1 else { continue }

            let joints = hand(wrist: wrist, fingers: fingers, backOfHand: back, isLeft: isLeft)
            guard let placement = WristMenuSolver.placement(
                joints: joints, isLeft: isLeft, head: head, panelHalfSize: panelHalfSize
            ), placement.facing > WristMenuSolver.showFacing else { continue }

            let toHead = normalize(head - placement.position)
            let up = SIMD3<Float>(0, 1, 0)
            let viewUpRaw = up - toHead * dot(up, toHead)
            guard length(viewUpRaw) > 0.05 else { continue }
            let viewUp = normalize(viewUpRaw)
            let viewRight = cross(viewUp, toHead)
            checked += 1

            // Elbow to fingertips.
            for step in 0...40 {
                let along = -0.26 + Float(step) * (0.44 / 40)
                let armPoint = wrist + normalize(fingers) * along
                // Project the arm point onto the menu's plane, from the head.
                let ray = armPoint - head
                let denominator = dot(ray, toHead)
                guard abs(denominator) > 1e-5 else { continue }
                let hit = head + ray * (dot(placement.position - head, toHead) / denominator)
                let offset = hit - placement.position
                let outsideX = abs(dot(offset, viewRight)) - panelHalfSize.x
                let outsideY = abs(dot(offset, viewUp)) - panelHalfSize.y
                XCTAssertGreaterThan(max(outsideX, outsideY), 0.01,
                                     "Arm crosses the menu (left: \(isLeft), fingers: \(fingers), back: \(back))")
            }
        }
        XCTAssertGreaterThan(checked, 200, "Too few poses exercised the check")
    }

    // MARK: - Smoothing

    func testFilterSettlesOnAStillPoint() {
        var filter = AdaptivePointFilter()
        let target = SIMD3<Float>(0.2, 1.1, -0.4)
        var output = SIMD3<Float>.zero
        for frame in 0..<180 {
            // ±1 mm of tracking jitter.
            let jitter = SIMD3<Float>(repeating: frame.isMultiple(of: 2) ? 0.001 : -0.001)
            output = filter.update(target + jitter, at: Double(frame) / 90)
        }
        XCTAssertLessThan(distance(output, target), 0.0008, "Jitter should be smoothed away at rest")
    }

    func testFilterKeepsUpWithAFastHand() {
        var filter = AdaptivePointFilter()
        var output = SIMD3<Float>.zero
        var raw = SIMD3<Float>.zero
        // 1 m/s along x at 90 Hz.
        for frame in 0..<90 {
            raw = SIMD3<Float>(Float(frame) / 90, 0, 0)
            output = filter.update(raw, at: Double(frame) / 90)
        }
        XCTAssertLessThan(distance(output, raw), 0.03, "Should trail a moving hand by under 3 cm")
        XCTAssertEqual(filter.speed, 1, accuracy: 0.25)
    }

    func testResetForgetsHistory() {
        var filter = AdaptivePointFilter()
        filter.update([0, 0, 0], at: 0)
        filter.update([1, 0, 0], at: 0.1)
        filter.reset()
        XCTAssertNil(filter.value)
        XCTAssertEqual(filter.update([5, 5, 5], at: 1), SIMD3<Float>(5, 5, 5))
    }
}
