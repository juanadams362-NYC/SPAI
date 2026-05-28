//
//  ImmersiveView.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//
//  Hosts the immersive space content: the existing RealityKit scene plus
//  our detection overlay floating in 3D world space.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    // Tonight we use hardcoded sample detections.
    // Tomorrow this becomes @State and gets populated from the backend.
    let detections: [Detection] = Detection.sampleDetections

    var body: some View {
        ZStack {
            // Existing RealityKit scene (skybox / starter content).
            RealityView { content in
                if let immersiveContentEntity = try? await Entity(
                    named: "Immersive",
                    in: realityKitContentBundle
                ) {
                    content.add(immersiveContentEntity)
                }
            }

            // Our detection overlay layered on top.
            DetectionOverlayView(detections: detections)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
