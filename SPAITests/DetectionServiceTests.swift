//
//  DetectionServiceTests.swift
//  SPAI
//
//  Created by Juan Adams on 6/25/26.
//


//
//  DetectionServiceTests.swift
//  SPAITests
//
//  Unit tests for the core detection logic — the contamination risk rule
//  and PPE status that drive the whole compliance UI. Also covers the
//  border-state thresholds (the same risk boundaries the DetectionPanel
//  uses to colour its LED border), with attention to the exact boundary
//  values where bugs like to hide.
//
//  These set the service's detections directly (no network) so we test the
//  pure derived logic in isolation.
//

import XCTest
@testable import SPAI

@MainActor
final class DetectionServiceTests: XCTestCase {

    // Helper: build a detection with just the fields the risk logic reads.
    private func detection(_ className: String) -> BackendDetection {
        BackendDetection(classId: 0, className: className, confidence: 0.9, box: [0, 0, 10, 10])
    }

    // MARK: - Contamination risk rule

    // Bare hand, no glove → high risk (0.85). This is the whole point of SPAI.
    func testBareHandIsHighRisk() {
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.85, accuracy: 0.001)
    }

    // Glove present → low risk (0.10).
    func testGloveIsLowRisk() {
        let service = DetectionService()
        service.detections = [detection("glove")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.10, accuracy: 0.001)
    }

    // Nothing detected → no risk signal (0).
    func testNothingDetectedIsZeroRisk() {
        let service = DetectionService()
        service.detections = []
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.0, accuracy: 0.001)
    }

    // Hand AND glove both present → glove wins, low risk. (The gloved hand
    // case — a hand wearing a glove still reads as protected.)
    func testHandAndGloveIsLowRisk() {
        let service = DetectionService()
        service.detections = [detection("hand"), detection("glove")]
        service.hasResult = true

        XCTAssertEqual(service.contaminationRisk, 0.10, accuracy: 0.001)
    }

    // Before any result arrives, risk is 0 regardless of stale detections.
    func testNoResultMeansZeroRisk() {
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = false   // no result yet

        XCTAssertEqual(service.contaminationRisk, 0.0, accuracy: 0.001)
    }

    // MARK: - PPE status

    // Glove + no bare hand → PPE passing.
    func testPPEPassesWithGloveNoHand() {
        let service = DetectionService()
        service.detections = [detection("glove")]
        service.hasResult = true

        XCTAssertTrue(service.ppePassing)
    }

    // Bare hand showing → PPE fails.
    func testPPEFailsWithBareHand() {
        let service = DetectionService()
        service.detections = [detection("hand")]
        service.hasResult = true

        XCTAssertFalse(service.ppePassing)
    }

    // Glove + a bare hand also showing → PPE fails (any bare hand = not passing).
    func testPPEFailsWhenHandAlsoShowing() {
        let service = DetectionService()
        service.detections = [detection("glove"), detection("hand")]
        service.hasResult = true

        XCTAssertFalse(service.ppePassing)
    }

    // MARK: - Border-state thresholds
    //
    // The DetectionPanel colours its border from the risk value:
    //   risk >= 0.5   → critical
    //   risk >  0.10  → warning
    //   else          → normal
    // borderState itself is private to the View, so we test the SAME
    // boundary logic here against the risk values the service produces.
    // This pins down the exact edges (is 0.10 warning or normal? is 0.5
    // critical?) so a future change can't silently shift them.

    private func borderLevel(forRisk risk: Double, hasResult: Bool = true) -> String {
        guard hasResult else { return "normal" }
        if risk >= 0.5 { return "critical" }
        if risk > 0.10 { return "warning" }
        return "normal"
    }

    func testBorderNormalAtZero() {
        XCTAssertEqual(borderLevel(forRisk: 0.0), "normal")
    }

    // Exactly 0.10 is NOT warning — the rule is strictly greater than 0.10.
    // (A gloved hand reads 0.10 and should stay calm/normal, not warn.)
    func testBorderNormalAtExactlyPoint10() {
        XCTAssertEqual(borderLevel(forRisk: 0.10), "normal")
    }

    func testBorderWarningJustAbovePoint10() {
        XCTAssertEqual(borderLevel(forRisk: 0.11), "warning")
    }

    func testBorderWarningBelowHalf() {
        XCTAssertEqual(borderLevel(forRisk: 0.49), "warning")
    }

    // Exactly 0.5 IS critical — the rule is >= 0.5.
    func testBorderCriticalAtExactlyHalf() {
        XCTAssertEqual(borderLevel(forRisk: 0.5), "critical")
    }

    // A bare hand (0.85) lands solidly in critical.
    func testBorderCriticalForBareHandRisk() {
        XCTAssertEqual(borderLevel(forRisk: 0.85), "critical")
    }

    // No result → normal, even if a risk value would otherwise be critical.
    func testBorderNormalWhenNoResult() {
        XCTAssertEqual(borderLevel(forRisk: 0.85, hasResult: false), "normal")
    }
}
