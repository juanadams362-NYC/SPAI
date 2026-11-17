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

    // MARK: - PPE overlap arbitration (real model outputs on images-18.jpeg)

    private func ppe(_ className: String, _ confidence: Double, _ box: [Int]) -> BackendDetection {
        BackendDetection(classId: className == "glove" ? 0 : 1, className: className, confidence: confidence, box: box)
    }

    func testDuplicateHandOnGlovedHandIsRemoved() {
        let out = DetectionService.resolvePPEOverlaps([
            ppe("glove", 0.73, [12, 101, 178, 199]),
            ppe("hand", 0.61, [16, 121, 187, 199])
        ])
        XCTAssertEqual(out.map(\.className), ["glove"])
    }

    func testGhostGloveOnBareHandIsRemoved() {
        let out = DetectionService.resolvePPEOverlaps([
            ppe("glove", 0.28, [135, 19, 224, 120]),
            ppe("hand", 0.80, [135, 23, 224, 115])
        ])
        XCTAssertEqual(out.map(\.className), ["hand"])
    }

    func testFragmentInsideStrongerBoxIsRemoved() {
        let out = DetectionService.resolvePPEOverlaps([
            ppe("glove", 0.73, [12, 101, 178, 199]),
            ppe("hand", 0.31, [68, 112, 177, 175])
        ])
        XCTAssertEqual(out.map(\.className), ["glove"])
    }

    func testTwoDifferentHandsAreBothKept() {
        let out = DetectionService.resolvePPEOverlaps([
            ppe("hand", 0.80, [135, 23, 224, 115]),
            ppe("glove", 0.73, [12, 101, 178, 199])
        ])
        XCTAssertEqual(Set(out.map(\.className)), ["hand", "glove"])
    }

    func testGlovedFrameNowPassesPPE() {
        // POV frame: before arbitration the duplicate "hand" made ppePassing false.
        let service = DetectionService()
        service.detections = DetectionService.resolvePPEOverlaps([
            ppe("glove", 0.90, [18, 17, 91, 123]),
            ppe("hand", 0.74, [18, 16, 91, 122]),
            ppe("glove", 0.67, [64, 115, 124, 174])
        ])
        service.hasResult = true
        XCTAssertTrue(service.ppePassing)
    }
}
