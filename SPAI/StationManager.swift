//
//  StationManager.swift
//  SPAI
//
//  Created by Juan Adams on 6/10/26.
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
    var onEnter: ((Station) -> Void)?

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

    func enter(_ station: Station) {
        guard activeStation?.id != station.id else { return }
        activeStation = station
        onEnter?(station)
    }

    func simulateScan(_ id: String) {
        guard let station = station(for: id) else { return }
        enter(station)
    }

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
