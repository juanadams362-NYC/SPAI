//
//  WristGestureTests.swift
//  SPAI
//

import XCTest
import simd
@testable import SPAI

final class WristGestureTests: XCTestCase {

    private let head = SIMD3<Float>(0, 1.5, 0)

    /// A wrist held in front of the user, with its face turned toward the head by `tilt`
    /// (1 = straight at the face, 0 = edge-on, -1 = turned away), and a forearm running
    /// horizontally unless `forearmY` says otherwise.
    private func pose(
        facingHead tilt: Float,
        forearmY: Float = 0,
        position: SIMD3<Float> = SIMD3<Float>(0, 1.2, -0.35)
    ) -> (position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>) {
        let toHead = normalize(head - position)
        // Build an "up" that has exactly `tilt` alignment with the direction to the head.
        let perpendicular = normalize(cross(toHead, SIMD3<Float>(1, 0, 0)))
        let up = normalize(toHead * tilt + perpendicular * sqrt(max(1 - tilt * tilt, 0)))
        let forward = normalize(SIMD3<Float>(1, forearmY, 0))
        return (position, forward, up)
    }

    // MARK: - Facing

    func testFacingIsHighWhenWristTurnedTowardHead() {
        let f = WristGesture.facing(pose: pose(facingHead: 1.0), headPosition: head)
        XCTAssertGreaterThan(f, 0.95)
    }

    func testFacingIsNegativeWhenWristTurnedAway() {
        let f = WristGesture.facing(pose: pose(facingHead: -1.0), headPosition: head)
        XCTAssertLessThan(f, -0.95)
    }

    func testFacingHandlesWristCoincidentWithHead() {
        // Degenerate input must not produce NaN and must not read as "presented".
        let degenerate = (position: head, forward: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 1, 0))
        let f = WristGesture.facing(pose: degenerate, headPosition: head)
        XCTAssertFalse(f.isNaN)
        XCTAssertLessThan(f, WristGesture.exitThreshold)
    }

    // MARK: - Right wrist: "checking the time"

    func testRightWristAppearsWhenTurnedTowardTheUser() {
        XCTAssertTrue(WristGesture.isPresented(
            pose: pose(facingHead: 0.9),
            headPosition: head,
            wasPresented: false,
            requireLevelForearm: false
        ))
    }

    func testRightWristStaysHiddenWhileArmIsDownAndTurnedAway() {
        XCTAssertFalse(WristGesture.isPresented(
            pose: pose(facingHead: 0.0),
            headPosition: head,
            wasPresented: false,
            requireLevelForearm: false
        ))
    }

    func testRightWristIgnoresForearmPitch() {
        // Checking a watch happens at all sorts of arm angles, so pitch must not gate it.
        let steep = pose(facingHead: 0.9, forearmY: 0.95)
        XCTAssertTrue(WristGesture.isPresented(
            pose: steep,
            headPosition: head,
            wasPresented: false,
            requireLevelForearm: false
        ))
    }

    // MARK: - Left forearm: "book on the forearm"

    func testLeftForearmAppearsWhenLevelAndTurnedUp() {
        XCTAssertTrue(WristGesture.isPresented(
            pose: pose(facingHead: 0.9, forearmY: 0),
            headPosition: head,
            wasPresented: false,
            requireLevelForearm: true
        ))
    }

    func testLeftForearmStaysHiddenWhenArmIsNotLevel() {
        // Correct rotation but the arm is pointing steeply up or down — not the book pose.
        XCTAssertFalse(WristGesture.isPresented(
            pose: pose(facingHead: 0.9, forearmY: 0.95),
            headPosition: head,
            wasPresented: false,
            requireLevelForearm: true
        ))
    }

    // MARK: - Hysteresis

    func testHysteresisKeepsAPresentedWristVisibleThroughTheBand() {
        // Mid-band: below the enter threshold, above the exit threshold.
        let midBand = (WristGesture.enterThreshold + WristGesture.exitThreshold) / 2
        let p = pose(facingHead: midBand)

        XCTAssertFalse(
            WristGesture.isPresented(pose: p, headPosition: head, wasPresented: false, requireLevelForearm: false),
            "should not switch on inside the band"
        )
        XCTAssertTrue(
            WristGesture.isPresented(pose: p, headPosition: head, wasPresented: true, requireLevelForearm: false),
            "should not switch off inside the band — this is what stops the panel strobing"
        )
    }

    func testEnterThresholdIsAboveExitThreshold() {
        XCTAssertGreaterThan(
            WristGesture.enterThreshold,
            WristGesture.exitThreshold,
            "inverted thresholds would make the hysteresis band amplify flicker instead of damping it"
        )
    }

    // MARK: - Missing inputs

    func testNoPoseMeansNoMenu() {
        XCTAssertFalse(WristGesture.isPresented(
            pose: nil,
            headPosition: head,
            wasPresented: true,
            requireLevelForearm: false
        ))
    }

    func testWithoutAHeadFixTheMenuFallsBackToTrackedMeansShown() {
        // Better a menu that appears too eagerly than one the user cannot summon at all.
        XCTAssertTrue(WristGesture.isPresented(
            pose: pose(facingHead: -1.0),
            headPosition: nil,
            wasPresented: false,
            requireLevelForearm: false
        ))
    }
}
