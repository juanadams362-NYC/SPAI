//
//  AppModelPanelTests.swift
//  SPAI
//

import XCTest
@testable import SPAI

@MainActor
final class AppModelPanelTests: XCTestCase {

    func testChatAndHistoryBothStartHidden() {
        let model = AppModel()
        XCTAssertFalse(model.isVisible("chat"))
        XCTAssertFalse(model.isVisible("history"))
    }

    func testHistoryTogglesExactlyLikeChat() {
        // The reported bug was "tap History does nothing, Chat works" — these two must stay
        // behaviourally identical, whatever else changes about placement.
        let model = AppModel()

        model.toggleVisibility("chat")
        model.toggleVisibility("history")
        XCTAssertTrue(model.isVisible("chat"))
        XCTAssertTrue(model.isVisible("history"))

        model.toggleVisibility("chat")
        model.toggleVisibility("history")
        XCTAssertFalse(model.isVisible("chat"))
        XCTAssertFalse(model.isVisible("history"))
    }

    func testOpeningAPanelRecordsItForTheEntranceAnimation() {
        let model = AppModel()

        model.toggleVisibility("history")

        XCTAssertEqual(model.lastOpenedPanel?.id, "history",
                       "the entrance animation needs to know which panel just opened")
    }

    func testClosingAPanelDoesNotRecordAnEntrance() {
        let model = AppModel()
        model.toggleVisibility("history")
        let opened = model.lastOpenedPanel?.at

        model.toggleVisibility("history")

        XCTAssertEqual(model.lastOpenedPanel?.at, opened,
                       "closing a panel must not trigger a fly-in")
    }

    func testOpeningChatAdvancesAWaitingTour() {
        let model = AppModel()
        model.tour.start()
        let chatStep = try! XCTUnwrap(model.tour.steps.firstIndex { $0.advanceOn == .openedChat })
        while model.tour.stepIndex < chatStep { model.tour.next() }

        model.toggleVisibility("chat")

        XCTAssertTrue(model.tour.justSatisfied,
                      "opening chat should satisfy the tour step that asks for it")
    }

    func testRoleChangeAdvancesAWaitingTour() {
        let model = AppModel()
        model.tour.start()
        let roleStep = try! XCTUnwrap(model.tour.steps.firstIndex { $0.advanceOn == .changedRole })
        while model.tour.stepIndex < roleStep { model.tour.next() }

        model.role = .trainee

        XCTAssertTrue(model.tour.justSatisfied)
    }

    func testSettingRoleToItsCurrentValueIsNotAChange() {
        let model = AppModel()
        model.tour.start()
        let roleStep = try! XCTUnwrap(model.tour.steps.firstIndex { $0.advanceOn == .changedRole })
        while model.tour.stepIndex < roleStep { model.tour.next() }

        model.role = .technician // already the default

        XCTAssertFalse(model.tour.justSatisfied,
                       "re-selecting the active role should not count as changing it")
    }

    func testShowAllPanelsRevealsChatAndHistory() {
        let model = AppModel()

        model.showAllPanels()

        XCTAssertTrue(model.isVisible("chat"))
        XCTAssertTrue(model.isVisible("history"))
    }

    // MARK: - Roles

    func testObserverAndSupervisorCannotRunTheWorkflow() {
        let model = AppModel()

        model.role = .observer
        XCTAssertFalse(model.canRunWorkflow)
        XCTAssertTrue(model.isReadOnly)

        model.role = .supervisor
        XCTAssertFalse(model.canRunWorkflow)

        model.role = .trainee
        XCTAssertTrue(model.canRunWorkflow)
    }

    func testStartStepIsRefusedForReadOnlyRoles() {
        let model = AppModel()
        model.role = .observer

        model.startStep()

        XCTAssertFalse(model.stepStarted, "an Observer must not be able to start a step")
    }
}
