//
//  OnDeviceDetector.swift
//  SPAI
//

import Vision
import CoreML
import UIKit

final class OnDeviceDetector {
    private let ppeModel: VNCoreMLModel?
    private let instrumentModel: VNCoreMLModel?

    init() {
        if let model = try? best(configuration: MLModelConfiguration()).model,
           let vn = try? VNCoreMLModel(for: model) {
            ppeModel = vn
        } else {
            ppeModel = nil
            print("[OnDeviceDetector] PPE model failed to load")
        }

        if let model = try? instruments_best(configuration: MLModelConfiguration()).model,
           let vn = try? VNCoreMLModel(for: model) {
            instrumentModel = vn
            print("[OnDeviceDetector] instrument model loaded")
        } else {
            instrumentModel = nil
            print("[OnDeviceDetector] instrument model failed to load")
        }
    }

    var isAvailable: Bool { ppeModel != nil }
    var hasInstruments: Bool { instrumentModel != nil }

    /// PPE detection — gloves and hands.
    func detect(image: UIImage) async -> [BackendDetection] {
        guard let ppeModel else { return [] }
        return await run(ppeModel, on: image) { label in
            label == "glove" ? 0 : 1
        }
    }

    /// Instrument detection. Each hit comes back under its catalog display
    /// name with its catalog key, matching what the backend's instrument
    /// endpoints return, so the rest of the app treats both sources alike.
    func detectInstruments(image: UIImage) async -> [BackendDetection] {
        guard let instrumentModel else { return [] }
        let raw = await run(instrumentModel, on: image) { label in
            let key = InstrumentCatalog.key(for: label)
            return InstrumentCatalog.all.firstIndex { $0.key == key } ?? 0
        }
        return raw.map { detection in
            BackendDetection(
                classId: detection.classId,
                className: InstrumentCatalog.displayName(for: detection.className),
                confidence: detection.confidence,
                box: detection.box,
                key: InstrumentCatalog.key(for: detection.className),
                category: InstrumentCatalog.genericLabel
            )
        }
    }

    private func run(
        _ model: VNCoreMLModel,
        on image: UIImage,
        classId: @escaping (String) -> Int
    ) async -> [BackendDetection] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
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
                        classId: classId(label.identifier),
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
