//
//  WorkspaceLayoutTests.swift
//  SPAITests
//
//  The Focus layout is the answer to "it's a lot to look at at once":
//  three panels open, everything else on request.
//

import XCTest
@testable import SPAI

@MainActor
final class WorkspaceLayoutTests: XCTestCase {

    func testFocusLayoutOpensOnlyTheEssentials() {
        let model = AppModel()
        model.layout = .focus
        model.panelVisibility.removeAll()

        for id in [PanelID.statusBar, PanelID.workflow, PanelID.detection] {
            XCTAssertTrue(model.isVisible(id), id)
        }
        for id in PanelID.optional {
            XCTAssertFalse(model.isVisible(id), id)
        }
    }

    func testEverythingLayoutOpensReferencePanels() {
        let model = AppModel()
        model.layout = .everything
        XCTAssertTrue(model.isVisible(PanelID.eventLog))
        XCTAssertTrue(model.isVisible(PanelID.upload))
        model.layout = .focus
    }

    func testTogglingAPanelOverridesTheLayoutDefault() {
        let model = AppModel()
        model.layout = .focus
        model.panelVisibility.removeAll()

        model.toggleVisibility(PanelID.chat)
        XCTAssertTrue(model.isVisible(PanelID.chat))
        model.toggleVisibility(PanelID.chat)
        XCTAssertFalse(model.isVisible(PanelID.chat))
    }

    func testGuideSpotlightRevealsAClosedPanel() {
        let model = AppModel()
        model.layout = .focus
        model.panelVisibility.removeAll()

        XCTAssertFalse(model.isShown(PanelID.eventLog))
        model.spotlightPanel = PanelID.eventLog
        XCTAssertTrue(model.isShown(PanelID.eventLog))
        XCTAssertFalse(model.isVisible(PanelID.eventLog), "Spotlight must not change the user's own choice")
    }
}
