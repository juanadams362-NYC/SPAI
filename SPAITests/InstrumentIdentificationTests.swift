//
//  InstrumentIdentificationTests.swift
//  SPAITests
//
//  Naming an instrument, choosing which one the user is showing, and only
//  announcing it once it has been seen steadily.
//

import XCTest
@testable import SPAI

@MainActor
final class InstrumentIdentificationTests: XCTestCase {

    private func detection(
        _ className: String,
        confidence: Double = 0.9,
        box: [Int] = [0, 0, 10, 10]
    ) -> BackendDetection {
        BackendDetection(classId: 0, className: className, confidence: confidence, box: box)
    }

    private func instrument(_ key: String, certain: Bool = true) -> IdentifiedInstrument {
        IdentifiedInstrument(key: key, name: key, confidence: 0.9, held: true, certain: certain, info: nil)
    }

    // MARK: - Catalog

    /// The label list baked into the instrument model's weights.
    private let modelLabels = [
        "Adson Dressing Forceps", "Babcock Tissue Forceps", "Halsted Mosquito Forceps",
        "Mayo Hegar Needle Holder", "Operating Scissors", "Scalpel Handle 3"
    ]

    func testEveryModelLabelHasAReferenceCard() {
        for label in modelLabels {
            XCTAssertNotNil(InstrumentCatalog.lookup(label), "No catalog entry for \(label)")
        }
        XCTAssertEqual(InstrumentCatalog.all.count, modelLabels.count)
    }

    func testLookupToleratesSpellingAndCase() {
        for label in ["Mayo Hegar Needle Holder", "mayo-hegar needle holder", " MAYO_HEGAR_NEEDLE_HOLDER ", "needle holder"] {
            XCTAssertEqual(InstrumentCatalog.lookup(label)?.key, "mayo_hegar_needle_holder", label)
        }
    }

    func testUnknownLabelFallsBackToItself() {
        XCTAssertNil(InstrumentCatalog.lookup("Kelly Clamp"))
        XCTAssertEqual(InstrumentCatalog.displayName(for: "Kelly Clamp"), "Kelly Clamp")
        XCTAssertEqual(InstrumentCatalog.displayName(for: "  "), "Instrument")
    }

    // MARK: - Which instrument is being shown

    func testNoInstrumentIdentifiesNothing() {
        XCTAssertNil(InstrumentIdentifier.identify(in: [detection("glove"), detection("hand")]))
    }

    func testHeldInstrumentBeatsAMoreConfidentOneOnTheBench() {
        let result = InstrumentIdentifier.identify(in: [
            detection("glove", box: [190, 150, 320, 300]),
            detection("Operating Scissors", confidence: 0.95, box: [600, 600, 700, 700]),
            detection("Mayo Hegar Needle Holder", confidence: 0.70, box: [100, 100, 200, 200])
        ])
        XCTAssertEqual(result?.key, "mayo_hegar_needle_holder")
        XCTAssertEqual(result?.name, "Mayo-Hegar Needle Holder")
        XCTAssertEqual(result?.held, true)
        XCTAssertEqual(result?.certain, true)
    }

    func testLowConfidenceIsNotNamed() {
        let result = InstrumentIdentifier.identify(in: [detection("Operating Scissors", confidence: 0.30)])
        XCTAssertEqual(result?.certain, false)
        XCTAssertEqual(result?.key, InstrumentCatalog.genericLabel)
        XCTAssertNil(result?.info)
    }

    func testGenericLabelFromOlderBackendIsNotNamed() {
        let result = InstrumentIdentifier.identify(in: [detection("instrument", confidence: 0.95)])
        XCTAssertEqual(result?.certain, false)
    }

    func testBackendHeldFlagIsTrusted() {
        var scissors = detection("Operating Scissors", confidence: 0.8, box: [600, 600, 700, 700])
        scissors.held = true
        XCTAssertEqual(InstrumentIdentifier.identify(in: [scissors])?.held, true)
    }

    // MARK: - Stability over time

    func testSingleFrameIsNotAnnounced() {
        var tracker = InstrumentTracker()
        XCTAssertNil(tracker.ingest(instrument("operating_scissors")))
        XCTAssertNil(tracker.current)
    }

    func testSteadyInstrumentIsAnnouncedOnce() {
        var tracker = InstrumentTracker()
        let now = Date()
        XCTAssertNil(tracker.ingest(instrument("operating_scissors"), at: now))
        XCTAssertEqual(tracker.ingest(instrument("operating_scissors"), at: now)?.key, "operating_scissors")
        XCTAssertEqual(tracker.current?.key, "operating_scissors")
        // Still in frame: stays current, but isn't said again.
        XCTAssertNil(tracker.ingest(instrument("operating_scissors"), at: now.addingTimeInterval(2)))
        XCTAssertEqual(tracker.current?.key, "operating_scissors")
    }

    func testFlickerBetweenTwoInstrumentsAnnouncesNeither() {
        var tracker = InstrumentTracker()
        for index in 0..<6 {
            let key = index.isMultiple(of: 2) ? "operating_scissors" : "scalpel_handle_3"
            XCTAssertNil(tracker.ingest(instrument(key)))
        }
    }

    func testInstrumentIsAnnouncedAgainAfterLeavingTheFrame() {
        var tracker = InstrumentTracker()
        let now = Date()
        _ = tracker.ingest(instrument("operating_scissors"), at: now)
        XCTAssertNotNil(tracker.ingest(instrument("operating_scissors"), at: now))

        _ = tracker.ingest(nil, at: now)
        _ = tracker.ingest(nil, at: now)
        XCTAssertNil(tracker.current)

        _ = tracker.ingest(instrument("operating_scissors"), at: now)
        XCTAssertNotNil(tracker.ingest(instrument("operating_scissors"), at: now))
    }

    func testOneDroppedFrameDoesNotClearTheInstrument() {
        var tracker = InstrumentTracker()
        _ = tracker.ingest(instrument("operating_scissors"))
        _ = tracker.ingest(instrument("operating_scissors"))
        _ = tracker.ingest(nil)
        XCTAssertEqual(tracker.current?.key, "operating_scissors")
    }

    func testUncertainSightingDoesNotTalkOverARecentName() {
        var tracker = InstrumentTracker()
        let now = Date()
        _ = tracker.ingest(instrument("operating_scissors"), at: now)
        XCTAssertNotNil(tracker.ingest(instrument("operating_scissors"), at: now))

        let unsure = instrument(InstrumentCatalog.genericLabel, certain: false)
        XCTAssertNil(tracker.ingest(unsure, at: now.addingTimeInterval(1)))
        XCTAssertNil(tracker.ingest(unsure, at: now.addingTimeInterval(2)))
    }
}
