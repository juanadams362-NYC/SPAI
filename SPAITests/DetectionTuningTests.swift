//
//  DetectionTuningTests.swift
//  SPAI
//

import XCTest
@testable import SPAI

@MainActor
final class DetectionTuningTests: XCTestCase {

    private func detection(
        _ className: String,
        confidence: Double = 0.9,
        box: [Int] = [0, 0, 100, 100]
    ) -> BackendDetection {
        BackendDetection(classId: 0, className: className, confidence: confidence, box: box)
    }

    // MARK: - Instrument vocabulary

    func testOnlyInstrumentLabelsCountAsInstruments() {
        // The chair bug: `isInstrumentClass` used to be "anything that isn't a glove or hand",
        // so any label the model invented satisfied an instrument step.
        XCTAssertTrue(DetectionService.isInstrumentClass("instrument"))
        XCTAssertTrue(DetectionService.isInstrumentClass("Operating Scissors"))
        XCTAssertTrue(DetectionService.isInstrumentClass("adson dressing forceps"))
        XCTAssertTrue(DetectionService.isInstrumentClass("Mayo Hegar Needle Holder"))
        // Shortened and re-cased variants still count — matching whole labels exactly would
        // fail closed on a real instrument the first time a label changed.
        XCTAssertTrue(DetectionService.isInstrumentClass("forceps"))
        XCTAssertTrue(DetectionService.isInstrumentClass("SCALPEL"))

        XCTAssertFalse(DetectionService.isInstrumentClass("chair"))
        XCTAssertFalse(DetectionService.isInstrumentClass("person"))
        XCTAssertFalse(DetectionService.isInstrumentClass("table"))
        XCTAssertFalse(DetectionService.isInstrumentClass("laptop"))
        XCTAssertFalse(DetectionService.isInstrumentClass(""))
    }

    func testEveryTrainedInstrumentClassIsRecognised() {
        // The six classes baked into instruments_best.mlpackage. If the model is retrained with
        // different names, this is the test that should fail rather than detections silently
        // being ignored.
        let trained = [
            "Adson Dressing Forceps",
            "Babcock Tissue Forceps",
            "Halsted Mosquito Forceps",
            "Mayo Hegar Needle Holder",
            "Operating Scissors",
            "Scalpel Handle 3"
        ]
        for label in trained {
            XCTAssertTrue(
                DetectionService.isInstrumentClass(label),
                "\(label) is a class the shipped model emits and must count as an instrument"
            )
        }
    }

    func testGlovesAndHandsAreNeverInstruments() {
        XCTAssertFalse(DetectionService.isInstrumentClass("glove"))
        XCTAssertFalse(DetectionService.isInstrumentClass("hand"))
        XCTAssertFalse(DetectionService.isInstrumentClass("bare_hand"))
    }

    // MARK: - Size plausibility

    func testChairSizedBoxIsRejectedAsAnInstrument() {
        // A box covering most of the frame is furniture, not something lying in a tray.
        let huge = DetectionTuning.isPlausible(
            box: [0, 0, 900, 900], imageWidth: 1000, imageHeight: 1000, isInstrument: true
        )
        XCTAssertFalse(huge)
    }

    func testTraySizedBoxIsAcceptedAsAnInstrument() {
        let modest = DetectionTuning.isPlausible(
            box: [100, 100, 400, 250], imageWidth: 1000, imageHeight: 1000, isInstrument: true
        )
        XCTAssertTrue(modest)
    }

    func testLargeBoxIsStillFineForPPE() {
        // A hand can legitimately fill a close-up frame; only instruments get the tight limit.
        let closeUp = DetectionTuning.isPlausible(
            box: [0, 0, 900, 900], imageWidth: 1000, imageHeight: 1000, isInstrument: false
        )
        XCTAssertTrue(closeUp)
    }

    func testDegenerateBoxesAreRejected() {
        XCTAssertFalse(DetectionTuning.isPlausible(
            box: [10, 10, 10, 10], imageWidth: 1000, imageHeight: 1000, isInstrument: true
        ))
        XCTAssertFalse(DetectionTuning.isPlausible(
            box: [0, 0, 10], imageWidth: 1000, imageHeight: 1000, isInstrument: true
        ))
        XCTAssertFalse(DetectionTuning.isPlausible(
            box: [0, 0, 10, 10], imageWidth: 0, imageHeight: 0, isInstrument: true
        ))
    }

    // MARK: - Combined filter

    func testFilterDropsAChairSizedInstrumentButKeepsAGlove() {
        let input = [
            detection("Operating Scissors", confidence: 0.9, box: [0, 0, 950, 950]),
            detection("glove", confidence: 0.6, box: [10, 10, 300, 300])
        ]
        let kept = DetectionService.filterImplausible(input, imageWidth: 1000, imageHeight: 1000)

        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.className, "glove")
    }

    func testInstrumentsNeedHigherConfidenceThanPPE() {
        let borderline = 0.40   // above the PPE floor, below the instrument floor
        XCTAssertGreaterThan(DetectionTuning.instrumentConfidence, borderline)
        XCTAssertLessThan(DetectionTuning.ppeConfidence, borderline)

        let input = [
            detection("instrument", confidence: borderline, box: [10, 10, 200, 200]),
            detection("hand", confidence: borderline, box: [10, 10, 200, 200])
        ]
        let kept = DetectionService.filterImplausible(input, imageWidth: 1000, imageHeight: 1000)

        XCTAssertEqual(kept.map(\.className), ["hand"],
                       "a marginal instrument should be dropped while marginal PPE is kept")
    }

    func testUnknownLabelsAreDroppedEntirely() {
        let input = [detection("chair", confidence: 0.99, box: [10, 10, 200, 200])]
        let kept = DetectionService.filterImplausible(input, imageWidth: 1000, imageHeight: 1000)
        XCTAssertTrue(kept.isEmpty, "a confident chair is still a chair")
    }

    // MARK: - Alert timing

    func testContaminationAlertIsNotDelayed() {
        // The safety signal must fire on the frame it appears. An earlier version of the
        // smoothing required two consecutive frames in both directions, which delayed it.
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.85, accuracy: 0.001)
    }

    func testClearFrameCountIsAboveOne() {
        XCTAssertGreaterThan(
            DetectionTuning.clearFrameCount, 1,
            "clearing on a single frame is what made the readout flicker"
        )
    }
}
