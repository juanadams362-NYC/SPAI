//
//  StationManager.swift
//  SPAI
//
//  Created by Juan Adams on 6/10/26.
//


import SwiftUI
import ARKit

// 1. What a station IS — id matches the reference-image name in your asset catalog
struct Station: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
@Observable
final class StationManager {
    var activeStation: Station?
    var onEnter: ((Station) -> Void)?        // the app wires this to openImmersiveSpace

    private let stations: [String: Station] = [
        "marker_prep_pack": Station(id: "marker_prep_pack", name: "Prep & Pack Bench")
    ]

    // The single funnel BOTH paths call — sim and hardware behave identically
    func enter(_ station: Station) {
        guard activeStation?.id != station.id else { return }
        activeStation = station
        onEnter?(station)
    }

    // SIM-TESTABLE today: call this from a debug button
    func simulateScan(_ id: String) {
        guard let station = stations[id] else { return }
        enter(station)
    }

    // REAL path (hardware only) — compiled out of the simulator
    #if !targetEnvironment(simulator)
    private let session = ARKitSession()

    func startImageTracking() async {
        guard ImageTrackingProvider.isSupported else { return }
        let refs = ReferenceImage.loadReferenceImages(inGroupNamed: "StationMarkers")
        let provider = ImageTrackingProvider(referenceImages: refs)
        do { try await session.run([provider]) }
        catch { print("[stations] ARKit failed: \(error)"); return }

        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked,
                  let name = anchor.referenceImage.name,
                  let station = stations[name] else { continue }
            enter(station)
        }
    }
    #endif
}
