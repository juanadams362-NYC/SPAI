//
//  OnDeviceDetector.swift
//  SPAI
//
//  Created by Juan Adams on 7/23/26.
//

import Vision
import CoreML
import UIKit

final class OnDeviceDetector {
    private let visionModel: VNCoreMLModel?

    init() {
        if let model = try? best(configuration: MLModelConfiguration()).model,
           let vnModel = try? VNCoreMLModel(for: model) {
            self.visionModel = vnModel
        } else {
            self.visionModel = nil
            print("[OnDeviceDetector] model failed to load — fallback unavailable")
        }
    }

    var isAvailable: Bool { visionModel != nil }

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
                    guard label.confidence >= 0.5 else { return nil }
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
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }
}
