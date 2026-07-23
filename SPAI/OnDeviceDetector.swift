//
//  OnDeviceDetector.swift
//  SPAI
//
//  Created by Juan Adams on 7/23/26.
//


//
//  OnDeviceDetector.swift
//  SPAI
//
//  Runs the PPE model directly on the device using Core ML + Vision.
//  Same trained weights as the backend, different container — this is
//  the fallback when the cloud is unreachable. No network, no Python.
//

import Vision
import CoreML
import UIKit

final class OnDeviceDetector {
    private let visionModel: VNCoreMLModel?

    init() {
        // Load once. If the model file is missing the detector just
        // reports unavailable instead of crashing the app.
        if let model = try? best(configuration: MLModelConfiguration()).model,
           let vnModel = try? VNCoreMLModel(for: model) {
            self.visionModel = vnModel
        } else {
            self.visionModel = nil
            print("[OnDeviceDetector] model failed to load — fallback unavailable")
        }
    }

    var isAvailable: Bool { visionModel != nil }

    /// Run detection on-device. Returns the same BackendDetection shape
    /// the cloud returns, so everything downstream works unchanged.
    func detect(image: UIImage) async -> [BackendDetection] {
        guard let visionModel, let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)

                let detections = observations.compactMap { obs -> BackendDetection? in
                    guard let label = obs.labels.first else { return nil }
                    // Vision boxes are normalized 0-1 with origin at
                    // BOTTOM-left. Backend boxes are pixels, TOP-left
                    // origin. Flip the y and scale to pixels so both
                    // paths produce identical data.
                    let box = obs.boundingBox
                    let x1 = Int(box.minX * width)
                    let y1 = Int((1 - box.maxY) * height)
                    let x2 = Int(box.maxX * width)
                    let y2 = Int((1 - box.minY) * height)

                    return BackendDetection(
                        classId: label.identifier == "glove" ? 0 : 1,
                        className: label.identifier,
                        confidence: Double(label.confidence),
                        box: [x1, y1, x2, y2]
                    )
                }
                continuation.resume(returning: detections)
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }
}