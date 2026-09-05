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

    // MARK: - Window toggles

    func testSettingsTogglesOpenThenClosed() async throws {
        let model = AppModel()

        XCTAssertEqual(model.requestSettingsToggle(), .open)
        XCTAssertTrue(model.isSettingsWindowOpen)

        // Past the debounce window, the next press must close it.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(model.requestSettingsToggle(), .close)
        XCTAssertFalse(model.isSettingsWindowOpen)
    }

    func testRapidSecondPressIsIgnored() {
        // The reported bug: repeated presses spawned window after window. A gaze-pinch can
        // register twice, and without debouncing that reads as open-then-instantly-close.
        let model = AppModel()

        XCTAssertEqual(model.requestSettingsToggle(), .open)
        XCTAssertEqual(model.requestSettingsToggle(), .ignore)
        XCTAssertEqual(model.requestSettingsToggle(), .ignore)
        XCTAssertTrue(model.isSettingsWindowOpen, "the window should still be open, exactly once")
    }

    func testUploadAndSettingsShareTheDebounce() {
        let model = AppModel()

        XCTAssertEqual(model.requestSettingsToggle(), .open)
        XCTAssertEqual(model.requestUploadToggle(), .ignore,
                       "a single mis-registered pinch must not open two different windows")
    }

    // MARK: - Action feedback

    func testTogglingAPanelAnnouncesWhatHappened() {
        let model = AppModel()

        model.toggleVisibility("history")
        XCTAssertEqual(model.lastAction?.message, "History opened")

        model.toggleVisibility("history")
        XCTAssertEqual(model.lastAction?.message, "History closed")
    }

    // MARK: - Wrist menus

    func testWristMenusDefaultOn() {
        // `bool(forKey:)` returns false for an unwritten key, which would ship the feature off.
        UserDefaults.standard.removeObject(forKey: "wristMenusEnabled")
        XCTAssertTrue(AppModel().wristMenusEnabled)
    }

    func testTourDropsWristInstructionsWhenWristMenusAreOff() {
        let withWrists = AppTour.script(wristMenusEnabled: true)
        let without = AppTour.script(wristMenusEnabled: false)

        XCTAssertTrue(withWrists.contains { $0.anchor == .wristMenu })
        XCTAssertFalse(
            without.contains { $0.anchor == .wristMenu },
            "the tour must not tell the user to tap a menu that cannot appear"
        )
        XCTAssertFalse(
            without.contains { ($0.callToAction ?? "").localizedCaseInsensitiveContains("wrist") },
            "no call to action should reference the wrist when wrist menus are disabled"
        )
    }

    func testTourStepIDsStaySequentialAfterFiltering() {
        let without = AppTour.script(wristMenusEnabled: false)
        XCTAssertEqual(without.map(\.id), Array(0..<without.count))
    }

    func testEveryWaitingStepIsStillReachableWithoutWristMenus() {
        // Each action the tour waits on has to be performable from somewhere else.
        let without = AppTour.script(wristMenusEnabled: false)
        for step in without where step.advanceOn != nil {
            XCTAssertNotNil(step.callToAction, "step \(step.id) waits with no instruction")
            XCTAssertNotEqual(step.anchor, .wristMenu)
        }
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
