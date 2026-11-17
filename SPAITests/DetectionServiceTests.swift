//
//  DetectionServiceTests.swift
//  SPAI
//
//  Created by Juan Adams on 6/25/26.
//

import XCTest
@testable import SPAI

@MainActor
final class DetectionServiceTests: XCTestCase {

    private func detection(_ className: String) -> BackendDetection {
        BackendDetection(classId: 0, className: className, confidence: 0.9, box: [0, 0, 10, 10])
    }

    // MARK: - Contamination risk rule

    func testBareHandIsHighRisk() {
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.85, accuracy: 0.001)
    }

    func testGloveIsLowRisk() {
        let service = DetectionService()
        service.detections = [detection("glove")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.10, accuracy: 0.001)
    }

    func testNothingDetectedIsZeroRisk() {
        let service = DetectionService()
        service.detections = []
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.0, accuracy: 0.001)
    }

    func testHandAndGloveIsLowRisk() {
        let service = DetectionService()
        service.detections = [detection("hand"), detection("glove")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.10, accuracy: 0.001)
    }

    func testNoResultMeansZeroRisk() {
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = false

        XCTAssertEqual(service.contaminationRisk, 0.0, accuracy: 0.001)
    }

    func testBareHandLabelIsHighRisk() {
        let service = DetectionService()
        service.detections = [detection("bare_hand")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.85, accuracy: 0.001)
    }

    // MARK: - PPE status

    func testPPEPassesWithGloveNoHand() {
        let service = DetectionService()
        service.detections = [detection("glove")]
        service.hasResult = true

        XCTAssertTrue(service.ppePassing)
    }

    func testPPEFailsWithBareHand() {
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = true

        XCTAssertFalse(service.ppePassing)
    }

    func testPPEClassifierRejectsInstrumentLabels() {
        XCTAssertTrue(DetectionService.isPPEClass("glove"))
        XCTAssertTrue(DetectionService.isPPEClass("bare_hand"))
        XCTAssertFalse(DetectionService.isPPEClass("forceps"))
        XCTAssertFalse(DetectionService.isPPEClass("instrument"))
    }

    func testSpecificInstrumentLabelsCountAsInstrumentDetections() {
        let service = DetectionService()
        service.detections = [detection("forceps")]
        service.hasResult = true

        XCTAssertTrue(service.hasInstrumentDetection)
    }

    func testPPEFailsWhenHandAlsoShowing() {
        let service = DetectionService()
        service.detections = [detection("glove"), detection("hand")]
        service.hasResult = true

        XCTAssertFalse(service.ppePassing)
    }

    // MARK: - Border-state thresholds

    private func borderLevel(forRisk risk: Double, hasResult: Bool = true) -> String {
        guard hasResult else { return "normal" }
        if risk >= 0.5 { return "critical" }
        if risk > 0.10 { return "warning" }
        return "normal"
    }

    func testBorderNormalAtZero() {
        XCTAssertEqual(borderLevel(forRisk: 0.0), "normal")
    }

    func testBorderNormalAtExactlyPoint10() {
        XCTAssertEqual(borderLevel(forRisk: 0.10), "normal")
    }

    func testBorderWarningJustAbovePoint10() {
        XCTAssertEqual(borderLevel(forRisk: 0.11), "warning")
    }

    func testBorderWarningBelowHalf() {
        XCTAssertEqual(borderLevel(forRisk: 0.49), "warning")
    }

    func testBorderCriticalAtExactlyHalf() {
        XCTAssertEqual(borderLevel(forRisk: 0.5), "critical")
    }

    func testBorderCriticalForBareHandRisk() {
        XCTAssertEqual(borderLevel(forRisk: 0.85), "critical")
    }

    func testBorderNormalWhenNoResult() {
        XCTAssertEqual(borderLevel(forRisk: 0.85, hasResult: false), "normal")
    }

    // MARK: - One hand, two boxes

    /// Boxes measured from the real glove model on demo/test-media/bare-hand.jpg.
    func testDoubleLabelledHandIsResolvedByConfidence() {
        let frame = [
            BackendDetection(classId: 1, className: "hand", confidence: 0.80, box: [135, 23, 224, 115]),
            BackendDetection(classId: 0, className: "glove", confidence: 0.28, box: [135, 19, 224, 120]),
            BackendDetection(classId: 0, className: "glove", confidence: 0.73, box: [12, 101, 178, 199]),
            BackendDetection(classId: 1, className: "hand", confidence: 0.61, box: [16, 121, 187, 199]),
            BackendDetection(classId: 1, className: "hand", confidence: 0.31, box: [68, 112, 177, 175])
        ]
        let hands = DetectionService.resolveHands(frame)
        XCTAssertEqual(hands.bare, 1, "The clearly bare hand must count even though a glove is also in view")
        XCTAssertGreaterThanOrEqual(hands.gloved, 1)

        let service = DetectionService()
        service.detections = frame
        service.hasResult = true
        XCTAssertEqual(service.contaminationRisk, 0.85, accuracy: 0.001)
        XCTAssertFalse(service.ppePassing)
    }

    /// Measured on docs/sprint-notes/week2-screenshots/pov_test_no_detections.jpg:
    /// the same gloved hand labelled both ways.
    func testSameHandLabelledBothWaysIsAGlove() {
        let frame = [
            BackendDetection(classId: 0, className: "glove", confidence: 0.90, box: [18, 17, 91, 123]),
            BackendDetection(classId: 1, className: "hand", confidence: 0.74, box: [18, 16, 91, 122]),
            BackendDetection(classId: 0, className: "glove", confidence: 0.67, box: [64, 115, 124, 174])
        ]
        let hands = DetectionService.resolveHands(frame)
        XCTAssertEqual(hands.bare, 0)
        XCTAssertEqual(hands.gloved, 2)
    }

    func testFaintBareHandDoesNotHaltTheWorkflow() {
        let frame = [BackendDetection(classId: 1, className: "hand", confidence: 0.35, box: [0, 0, 50, 50])]
        XCTAssertEqual(DetectionService.resolveHands(frame).bare, 0)
    }

    // MARK: - Box arbitration (what gets stored and drawn)

    func testArbitrationKeepsOneBoxPerHand() {
        let raw = [
            BackendDetection(classId: 1, className: "hand", confidence: 0.80, box: [135, 23, 224, 115]),
            BackendDetection(classId: 0, className: "glove", confidence: 0.28, box: [135, 19, 224, 120]),
            BackendDetection(classId: 0, className: "glove", confidence: 0.73, box: [12, 101, 178, 199]),
            BackendDetection(classId: 1, className: "hand", confidence: 0.61, box: [16, 121, 187, 199]),
            BackendDetection(classId: 1, className: "hand", confidence: 0.31, box: [68, 112, 177, 175])
        ]
        let out = DetectionService.resolvePPEOverlaps(raw)
        XCTAssertEqual(out.map(\.className).sorted(), ["glove", "hand"])
        // The safety verdict is unchanged by cleaning the boxes.
        let hands = DetectionService.resolveHands(out)
        XCTAssertEqual(hands.bare, 1)
        XCTAssertEqual(hands.gloved, 1)
    }

    func testHandFragmentInsideGloveBoxIsRemoved() {
        // IoU 0.42 — under the 0.5 same-hand line — but most of it sits inside the glove box.
        let out = DetectionService.resolvePPEOverlaps([
            BackendDetection(classId: 0, className: "glove", confidence: 0.73, box: [12, 101, 178, 199]),
            BackendDetection(classId: 1, className: "hand", confidence: 0.61, box: [68, 112, 177, 175])
        ])
        XCTAssertEqual(out.map(\.className), ["glove"])
    }

    func testArbitrationTieGoesToGlove() {
        let out = DetectionService.resolvePPEOverlaps([
            BackendDetection(classId: 1, className: "hand", confidence: 0.6, box: [0, 0, 100, 100]),
            BackendDetection(classId: 0, className: "glove", confidence: 0.6, box: [2, 2, 100, 100])
        ])
        XCTAssertEqual(out.map(\.className), ["glove"])
    }
}
