//
//  OnDeviceDetector.swift
//  SPAI
//

import Vision
import CoreML
import UIKit
import ImageIO

final class OnDeviceDetector {
    private let ppeModel: VNCoreMLModel?
    private let instrumentModel: VNCoreMLModel?

    init() {
        // Let CoreML pick the fastest available compute unit, but fall back if the Neural
        // Engine path refuses to compile — in the simulator it does, logging
        // "MpsGraph backend validation on incompatible OS", and the model then fails to load
        // at all rather than quietly running on CPU.
        ppeModel = Self.loadModel(
            named: "PPE",
            build: { try best(configuration: $0).model }
        )
        instrumentModel = Self.loadModel(
            named: "instrument",
            build: { try instruments_best(configuration: $0).model }
        )
    }

    private static func loadModel(
        named name: String,
        build: (MLModelConfiguration) throws -> MLModel
    ) -> VNCoreMLModel? {
        for units in [MLComputeUnits.all, .cpuAndGPU, .cpuOnly] {
            let config = MLModelConfiguration()
            config.computeUnits = units
            do {
                let vn = try VNCoreMLModel(for: try build(config))
                print("[OnDeviceDetector] \(name) model loaded (\(units))")
                return vn
            } catch {
                print("[OnDeviceDetector] \(name) model failed on \(units): \(error.localizedDescription)")
            }
        }
        print("[OnDeviceDetector] \(name) model unavailable")
        return nil
    }

    var isAvailable: Bool { ppeModel != nil }
    var hasInstruments: Bool { instrumentModel != nil }

    /// PPE detection — gloves and hands.
    func detect(image: UIImage) async -> [BackendDetection] {
        guard let ppeModel else { return [] }
        return await run(
            ppeModel,
            on: image,
            confidence: DetectionTuning.ppeConfidence,
            isInstrument: false,
            classId: { DetectionTuning.normalized($0) == "glove" ? 0 : 1 },
            rename: { $0 }
        )
    }

    func detectInstruments(image: UIImage) async -> [BackendDetection] {
        guard let instrumentModel else { return [] }
        return await run(
            instrumentModel,
            on: image,
            confidence: DetectionTuning.instrumentConfidence,
            isInstrument: true,
            classId: { _ in 0 },
            // Match what the backend reports. The model's six class names are not trustworthy
            // — it collapses to one in practice — and only the count matters for loaded/empty.
            rename: { _ in DetectionTuning.instrumentDisplayLabel }
        )
    }

    private func run(
        _ model: VNCoreMLModel,
        on image: UIImage,
        confidence: Double,
        isInstrument: Bool,
        classId: @escaping (String) -> Int,
        rename: @escaping (String) -> String
    ) async -> [BackendDetection] {
        guard let cgImage = image.cgImage else { return [] }

        // Vision reads the raw pixel buffer and knows nothing about UIImage's orientation flag.
        // A photo from the camera roll or an iPhone camera is almost always stored rotated with
        // an orientation tag, so passing the CGImage alone fed the model a sideways picture —
        // which is out of distribution and returns nothing. The backend already did the
        // equivalent (`ImageOps.exif_transpose`), so cloud worked and on-device silently did
        // not. This is the most likely cause of "sometimes it won't detect anything".
        let orientation = Self.cgOrientation(from: image.imageOrientation)

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error {
                    print("[OnDeviceDetector] request failed: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Bounding boxes come back normalised to the *oriented* image, so measure
                // against the oriented dimensions or every box is wrong on a rotated photo.
                let upright = orientation == .left || orientation == .right
                    || orientation == .leftMirrored || orientation == .rightMirrored
                let width = CGFloat(upright ? cgImage.height : cgImage.width)
                let height = CGFloat(upright ? cgImage.width : cgImage.height)

                var kept: [BackendDetection] = []
                var rejected = 0

                for obs in observations {
                    guard let label = obs.labels.first else { continue }
                    guard Double(label.confidence) >= confidence else { rejected += 1; continue }

                    let box = obs.boundingBox
                    let x1 = Int(box.minX * width)
                    let y1 = Int((1 - box.maxY) * height)
                    let x2 = Int(box.maxX * width)
                    let y2 = Int((1 - box.minY) * height)
                    let pixels = [x1, y1, x2, y2]

                    guard DetectionTuning.isPlausible(
                        box: pixels,
                        imageWidth: Int(width),
                        imageHeight: Int(height),
                        isInstrument: isInstrument
                    ) else {
                        rejected += 1
                        continue
                    }

                    kept.append(BackendDetection(
                        classId: classId(label.identifier),
                        className: rename(label.identifier),
                        confidence: Double(label.confidence),
                        box: pixels
                    ))
                }

                if rejected > 0 {
                    print("[OnDeviceDetector] kept \(kept.count), rejected \(rejected) (confidence/size)")
                }
                continuation.resume(returning: kept)
            }

            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                print("[OnDeviceDetector] handler failed: \(error.localizedDescription)")
                continuation.resume(returning: [])
            }
        }
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
