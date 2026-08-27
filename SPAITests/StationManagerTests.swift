//
//  StationManagerTests.swift
//  SPAI
//
//  Created by Juan Adams on 6/25/26.
//

import XCTest
@testable import SPAI

@MainActor
final class StationManagerTests: XCTestCase {

    func testFiveStationsWithUniqueIDs() {
        let manager = StationManager()
        XCTAssertEqual(manager.stations.count, 5, "expected one station per sterile step")

        let ids = manager.stations.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "station ids must be unique")
    }

    func testEnterSetsActiveStation() {
        let manager = StationManager()
        let first = manager.stations[0]

        manager.enter(first)

        XCTAssertEqual(manager.activeStation?.id, first.id)
    }

    func testEnterFiresCallback() {
        let manager = StationManager()
        var callbackCount = 0
        manager.onEnter = { _ in callbackCount += 1 }

        manager.enter(manager.stations[0])

        XCTAssertEqual(callbackCount, 1, "onEnter should fire once on a new station")
    }

    func testEnteringSameStationTwiceDoesNotRefire() {
        let manager = StationManager()
        var callbackCount = 0
        manager.onEnter = { _ in callbackCount += 1 }

        let station = manager.stations[0]
        manager.enter(station)
        manager.enter(station)

        XCTAssertEqual(callbackCount, 1, "re-entering the same station must not re-fire")
    }

    func testEnteringDifferentStationRefires() {
        let manager = StationManager()
        var callbackCount = 0
        manager.onEnter = { _ in callbackCount += 1 }

        manager.enter(manager.stations[0])
        manager.enter(manager.stations[1])

        XCTAssertEqual(callbackCount, 2, "moving to a new station should fire again")
    }

    func testSimulateScanEntersMatchingStation() {
        let manager = StationManager()
        let target = manager.stations[2]

        manager.simulateScan(target.id)

        XCTAssertEqual(manager.activeStation?.id, target.id,
                       "simulateScan should enter the station matching the id")
    }

    func testSimulateScanWithUnknownIDDoesNothing() {
        let manager = StationManager()

        manager.simulateScan("marker_does_not_exist")

        XCTAssertNil(manager.activeStation, "unknown marker id should leave no active station")
    }
}