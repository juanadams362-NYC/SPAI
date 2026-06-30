//
//  CVPixelBuffer+UIImage.swift
//  SPAI
//
//  Bridges the camera's frame buffers to UIImage, so live camera frames
//  can flow through the SAME DetectionService.detect(image:) path the
//  upload flow already uses. One detection pipeline, two input sources
//  (upload on sim, camera on hardware).
//
//  visionOS 26: the main camera hands back a CVReadOnlyPixelBuffer (an
//  immutable wrapper). It exposes the real CVPixelBuffer through a
//  withUnsafeBuffer { } closure — we render the image inside that scope.
//

import UIKit
import CoreImage
import CoreVideo

extension UIImage {
    /// Build a UIImage from the camera's read-only pixel buffer.
    /// Returns nil if the buffer can't be rendered.
    static func from(readOnlyBuffer: CVReadOnlyPixelBuffer) -> UIImage? {
        readOnlyBuffer.withUnsafeBuffer { pixelBuffer -> UIImage? in
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
    }
}
