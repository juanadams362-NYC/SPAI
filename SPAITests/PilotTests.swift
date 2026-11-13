//
//  PilotTests.swift
//  SPAITests
//
//  Scoring and the count sheet. The scoring cases mirror
//  backend/tests/test_pilot.py: the headset and the server must agree.
//

import XCTest
@testable import SPAI

@MainActor
final class PilotTests: XCTestCase {

    private func event(_ kind: String, _ station: SterileStep) -> RunEvent {
        RunEvent(at: "2026-11-12T10:00:00Z", kind: kind, station: station.backendName, message: kind)
    }

    private var cleanRun: [RunEvent] {
        SterileStep.allCases.flatMap { [event("station_start", $0), event("station_complete", $0)] }
    }

    // MARK: - Scoring

    func testCleanRunIsCompetentWithFullMarks() {
        let result = Competency.score(events: cleanRun, completed: true, stationsCompleted: 5)
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.verdict, .competent)
        XCTAssertTrue(result.deductions.isEmpty)
        XCTAssertEqual(result.coaching, ["Clean run. Every station completed with no alerts."])
    }

    func testOneContaminationFailsCompetencyEvenAtAPassingScore() {
        let result = Competency.score(events: cleanRun + [event("contamination", .inspection)],
                                      completed: true, stationsCompleted: 5)
        XCTAssertEqual(result.score, 80)
        XCTAssertEqual(result.verdict, .needsPractice)
        XCTAssertTrue(result.coaching.contains { $0.contains("Inspection") })
    }

    func testDeductionsAddUpAndNeverGoBelowZero() {
        var events = cleanRun + [event("send_back", .trayAssembly), event("redo", .packaging),
                                 event("count_mismatch", .trayAssembly)]
        XCTAssertEqual(Competency.score(events: events, completed: true, stationsCompleted: 5).score, 75)
        events += Array(repeating: event("contamination", .decontamination), count: 9)
        XCTAssertEqual(Competency.score(events: events, completed: true, stationsCompleted: 5).score, 0)
    }

    func testUnfinishedRunIsIncomplete() {
        let result = Competency.score(events: [], completed: false, stationsCompleted: 2)
        XCTAssertEqual(result.verdict, .incomplete)
        XCTAssertTrue(result.coaching.last?.contains("Tray Assembly") ?? false)
    }

    func testInstitutionRubricChangesTheVerdict() {
        let events = cleanRun + [event("redo", .packaging)]
        XCTAssertEqual(Competency.score(events: events, completed: true, stationsCompleted: 5).verdict, .competent)
        XCTAssertEqual(Competency.score(events: events, completed: true, stationsCompleted: 5,
                                        rubric: ["redo_penalty": 30]).verdict, .needsPractice)
    }

    // MARK: - Count sheet

    private let sheet = SiteProtocol.CountSheet(id: "s", name: "Test Set", items: [
        .init(key: "operating_scissors", name: "Operating Scissors", count: 2),
        .init(key: "scalpel_handle_3", name: "Scalpel Handle No. 3", count: 1)
    ])

    func testExactCountMatches() {
        let check = CountSheetCheck.check(sheet: sheet, seen: ["operating_scissors": 2, "scalpel_handle_3": 1])
        XCTAssertTrue(check.matches)
        XCTAssertEqual(check.summary, "Count matches the sheet")
    }

    func testMissingInstrumentIsNamed() {
        let check = CountSheetCheck.check(sheet: sheet, seen: ["operating_scissors": 1, "scalpel_handle_3": 1])
        XCTAssertFalse(check.matches)
        XCTAssertEqual(check.summary, "Operating Scissors missing")
    }

    func testExtraAndUnlistedInstrumentsFailTheCount() {
        let extra = CountSheetCheck.check(sheet: sheet, seen: ["operating_scissors": 3, "scalpel_handle_3": 1])
        XCTAssertFalse(extra.matches)
        XCTAssertEqual(extra.summary, "extra Operating Scissors")

        let unlisted = CountSheetCheck.check(sheet: sheet, seen: ["operating_scissors": 2, "scalpel_handle_3": 1,
                                                                 "babcock_tissue_forceps": 1])
        XCTAssertFalse(unlisted.matches)
        XCTAssertEqual(unlisted.unexpected, ["Babcock Tissue Forceps"])
    }

    func testEmptyTrayMatchesNothing() {
        XCTAssertFalse(CountSheetCheck.check(sheet: sheet, seen: [:]).matches)
    }

    // MARK: - Protocol

    func testStandardProtocolHasACountStepAtTrayAssembly() {
        XCTAssertTrue(StationScripts.standard(for: .trayAssembly).contains { $0.condition == .countMatches })
        for step in SterileStep.allCases {
            XCTAssertFalse(StationScripts.standard(for: step).isEmpty)
        }
    }

    func testServerProtocolDecodes() throws {
        let json = """
        {"name": "Our protocol", "version": 3, "updated_at": null, "is_standard": false,
         "stations": [{"key": "decontamination", "title": "Decontamination",
                       "steps": [{"instruction": "Gown up.", "condition": "gloves_on", "why": "Splash."}]}],
         "count_sheets": [{"id": "a", "name": "Set A", "items": [{"key": "operating_scissors", "name": "Operating Scissors", "count": 2}]}],
         "rubric": {"pass_score": 85}}
        """
        let decoded = try JSONDecoder().decode(SiteProtocol.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.stations.first?.steps.first?.condition, "gloves_on")
        XCTAssertEqual(decoded.countSheets.first?.items.first?.count, 2)
        XCTAssertEqual(decoded.rubric["pass_score"], 85)
    }

    func testRunRecordEncodesWithServerFieldNames() throws {
        let run = RunRecord(id: "run-1", learnerID: "abc", learnerName: "Avery", role: "Trainee", mode: "assessed",
                            headset: "Lab 1", startedAt: "a", endedAt: "b", durationSeconds: 60, completed: true,
                            stationsCompleted: 5, events: [], instrumentsSeen: ["Operating Scissors"],
                            appVersion: "1.0", detectionMode: "On-Device")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any]
        XCTAssertEqual(object?["learner_id"] as? String, "abc")
        XCTAssertEqual(object?["duration_s"] as? Int, 60)
        XCTAssertEqual(object?["stations_completed"] as? Int, 5)
        XCTAssertNotNil(object?["instruments_seen"])
    }
}
