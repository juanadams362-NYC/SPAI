//
//  StationManager.swift
//  SPAI
//
//  Created by Juan Adams on 6/10/26.
//
//  Tracks which station the user is at. One station per sterile step.
//  enter() is the single funnel both the sim picker and the hardware
//  image-tracker call, so they behave identically. Entering a station
//  sets it active, logs it, and moves the workflow to that step (a + b).
//  Per-station 3D environments (c) are a future sprint item.
//

import SwiftUI
import ARKit

struct Station: Identifiable, Hashable {
    let id: String
    let name: String
    let step: SterileStep
}

@MainActor
@Observable
final class StationManager {
    var activeStation: Station?
    /// The app wires this to react to a station change (set workflow, log, etc.)
    var onEnter: ((Station) -> Void)?
    
    /// One station per step. The id matches the reference-image name in the
    /// asset catalog for hardware marker tracking.
    let stations: [Station] = [
        Station(id: "marker_decon",     name: "Decontamination", step: .decontamination),
        Station(id: "marker_inspect",   name: "Inspection",      step: .inspection),
        Station(id: "marker_assembly",  name: "Tray Assembly",   step: .trayAssembly),
        Station(id: "marker_prep_pack", name: "Prep & Pack Bench", step: .packaging),
        Station(id: "marker_seal",      name: "Seal Validation", step: .sealValidation)
    ]
    
    private func station(for id: String) -> Station? {
        stations.first { $0.id == id }
    }
    
    /// The single funnel BOTH paths call — sim and hardware behave identically.
    func enter(_ station: Station) {
        guard activeStation?.id != station.id else { return }
        activeStation = station
        onEnter?(station)
    }
    
    /// SIM-TESTABLE today: call from the station picker.
    func simulateScan(_ id: String) {
        guard let station = station(for: id) else { return }
        enter(station)
    }
    
    // REAL path (hardware only) — compiled out of the simulator.
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
                  let station = station(for: name) else { continue }
            enter(station)
        }
    }
#endif // !targetEnvironment(simulator)
}
