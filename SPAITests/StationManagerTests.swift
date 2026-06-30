//
//  StationManagerTests.swift
//  SPAI
//
//  Created by Juan Adams on 6/25/26.
//


//
//  StationManagerTests.swift
//  SPAITests
//
//  Unit tests for the station-tracking logic that does NOT need hardware.
//  StationManager.enter() is the shared funnel both the sim picker and the
//  hardware image-tracker call, so testing it proves the core behavior is
//  correct regardless of which input path triggers it.
//

import XCTest
@testable import SPAI

@MainActor
final class StationManagerTests: XCTestCase {

    // There should be exactly one station per sterile step, and each marker
    // id should be unique (since it maps to a reference-image name).
    func testFiveStationsWithUniqueIDs() {
        let manager = StationManager()
        XCTAssertEqual(manager.stations.count, 5, "expected one station per sterile step")

        let ids = manager.stations.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "station ids must be unique")
    }

    // Entering a station should make it the active station.
    func testEnterSetsActiveStation() {
        let manager = StationManager()
        let first = manager.stations[0]

        manager.enter(first)

        XCTAssertEqual(manager.activeStation?.id, first.id)
    }

    // enter() should fire the onEnter callback exactly once per NEW station.
    func testEnterFiresCallback() {
        let manager = StationManager()
        var callbackCount = 0
        manager.onEnter = { _ in callbackCount += 1 }

        manager.enter(manager.stations[0])

        XCTAssertEqual(callbackCount, 1, "onEnter should fire once on a new station")
    }

    // Entering the SAME station twice should NOT re-fire (the dedup guard).
    // This matters on hardware: the image-tracker streams many updates for a
    // marker it's continuously seeing — we only want to react on first arrival.
    func testEnteringSameStationTwiceDoesNotRefire() {
        let manager = StationManager()
        var callbackCount = 0
        manager.onEnter = { _ in callbackCount += 1 }

        let station = manager.stations[0]
        manager.enter(station)
        manager.enter(station)   // same station again

        XCTAssertEqual(callbackCount, 1, "re-entering the same station must not re-fire")
    }

    // Moving to a DIFFERENT station should fire again.
    func testEnteringDifferentStationRefires() {
        let manager = StationManager()
        var callbackCount = 0
        manager.onEnter = { _ in callbackCount += 1 }

        manager.enter(manager.stations[0])
        manager.enter(manager.stations[1])   // different station

        XCTAssertEqual(callbackCount, 2, "moving to a new station should fire again")
    }

    // simulateScan() (the sim path) should funnel through enter() — proving
    // the sim demo drives the exact same behavior as the hardware tracker.
    func testSimulateScanEntersMatchingStation() {
        let manager = StationManager()
        let target = manager.stations[2]

        manager.simulateScan(target.id)

        XCTAssertEqual(manager.activeStation?.id, target.id,
                       "simulateScan should enter the station matching the id")
    }

    // simulateScan() with an unknown id should do nothing (no crash, no change).
    func testSimulateScanWithUnknownIDDoesNothing() {
        let manager = StationManager()

        manager.simulateScan("marker_does_not_exist")

        XCTAssertNil(manager.activeStation, "unknown marker id should leave no active station")
    }
}