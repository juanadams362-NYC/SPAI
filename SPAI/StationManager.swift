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
        guard ImageTrackingProvider.isSupported else {
            SPAILog.error(.stations, "ImageTrackingProvider not supported on this device")
            return
        }

        let refs = ReferenceImage.loadReferenceImages(inGroupNamed: "StationMarkers")
        // ARKit's own failure here is a low-level, easy-to-miss console line
        // ("ar_image_tracking_provider_t ... No images were supplied") that gives no hint
        // *why* — this is the actionable version: the group is either missing or every
        // `.arreferenceimage` inside it failed to load. Station entry then falls back to
        // whatever manual picker the UI offers, same as it would with the feature off.
        guard !refs.isEmpty else {
            SPAILog.error(.stations, "no reference images loaded from asset group \"StationMarkers\" — only the manual station picker will work until markers are registered")
            return
        }

        let provider = ImageTrackingProvider(referenceImages: refs)
        do { try await session.run([provider]) }
        catch { SPAILog.error(.stations, "ARKit failed: \(error)"); return }

        SPAILog.info(.stations, "image tracking started with \(refs.count) reference image(s)")

        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked, let name = anchor.referenceImage.name else { continue }
            guard let station = station(for: name) else {
                // Every name here came from an image we registered ourselves, so this is not
                // a stray marker in view — it means a `.arreferenceimage` was named something
                // that doesn't match any `Station.id`. Debug-level: a one-time setup mismatch
                // to catch while wiring markers up, not an ongoing health signal to alarm on
                // every time this anchor updates.
                SPAILog.debug(.stations, "tracked reference image \"\(name)\" doesn't match any known station id")
                continue
            }
            enter(station)
        }
    }
#endif // !targetEnvironment(simulator)
}
