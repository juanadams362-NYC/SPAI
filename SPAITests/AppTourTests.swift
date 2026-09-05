//
//  AppTourTests.swift
//  SPAI
//

import XCTest
@testable import SPAI

@MainActor
final class AppTourTests: XCTestCase {

    // MARK: - Phases

    func testStartsIdleAndOffersOnce() {
        let tour = AppTour()
        XCTAssertEqual(tour.phase, .idle)
        XCTAssertFalse(tour.isVisible)

        tour.offer()
        XCTAssertEqual(tour.phase, .offered)
        XCTAssertTrue(tour.isVisible)
    }

    func testOfferDoesNotInterruptARunningTour() {
        let tour = AppTour()
        tour.start()
        tour.next()

        tour.offer()

        XCTAssertEqual(tour.phase, .running, "a second offer must not reset a tour in progress")
        XCTAssertEqual(tour.stepIndex, 1)
    }

    func testNextAdvancesAndFinishesAtTheEnd() {
        let tour = AppTour()
        tour.start()

        for _ in 0..<(tour.steps.count - 1) { tour.next() }
        XCTAssertEqual(tour.phase, .running)
        XCTAssertEqual(tour.stepIndex, tour.steps.count - 1)

        tour.next()
        XCTAssertEqual(tour.phase, .finished, "advancing past the last step ends the tour")
    }

    func testBackStopsAtFirstStep() {
        let tour = AppTour()
        tour.start()

        tour.back()

        XCTAssertEqual(tour.stepIndex, 0, "back on the first step must not go negative")
    }

    func testSkipReturnsToIdle() {
        let tour = AppTour()
        tour.start()
        tour.next()

        tour.skip()

        XCTAssertEqual(tour.phase, .idle)
        XCTAssertEqual(tour.stepIndex, 0)
        XCTAssertFalse(tour.isVisible)
    }

    // MARK: - Learn-by-doing

    func testMatchingEventSatisfiesTheWaitingStep() {
        let tour = AppTour()
        tour.start()

        // Walk to the first step that waits on a real action.
        let waiting = tour.steps.firstIndex { $0.advanceOn != nil }
        let waitingIndex = try! XCTUnwrap(waiting)
        while tour.stepIndex < waitingIndex { tour.next() }

        let expected = tour.currentStep?.advanceOn
        tour.note(try! XCTUnwrap(expected))

        XCTAssertTrue(tour.justSatisfied, "the step should acknowledge the action immediately")
    }

    func testUnrelatedEventDoesNotAdvance() {
        let tour = AppTour()
        tour.start()

        let waitingIndex = try! XCTUnwrap(tour.steps.firstIndex { $0.advanceOn != nil })
        while tour.stepIndex < waitingIndex { tour.next() }

        let wrongEvent: TourEvent = tour.currentStep?.advanceOn == .changedRole ? .openedChat : .changedRole
        tour.note(wrongEvent)

        XCTAssertFalse(tour.justSatisfied)
        XCTAssertEqual(tour.stepIndex, waitingIndex, "an unrelated action must not advance the tour")
    }

    func testEventsAreIgnoredWhenTourIsNotRunning() {
        let tour = AppTour()

        tour.note(.startedStep)

        XCTAssertEqual(tour.phase, .idle)
        XCTAssertFalse(tour.justSatisfied, "the app's normal use must not wake a dismissed tour")
    }

    // MARK: - Script integrity

    func testEveryWaitingStepGivesTheUserAnInstruction() {
        for step in AppTour().steps where step.advanceOn != nil {
            XCTAssertNotNil(
                step.callToAction,
                "step \(step.id) waits on an action but never tells the user to perform it"
            )
        }
    }

    func testStepIDsAreSequential() {
        let steps = AppTour().steps
        XCTAssertEqual(steps.map(\.id), Array(0..<steps.count))
    }

    func testEveryAnchorResolvesToARealPanel() {
        // Anchors are matched to RealityKit attachment IDs by raw value, so a typo here would
        // silently park the coachmark in the middle of the room instead of beside its subject.
        let known: Set<String> = [
            "center", "statusBar", "detection", "eventLog",
            "workflow", "guided", "upload", "wristMenu"
        ]
        for step in AppTour().steps {
            XCTAssertTrue(
                known.contains(step.anchor.rawValue),
                "step \(step.id) points at unknown anchor \(step.anchor.rawValue)"
            )
        }
    }
}
