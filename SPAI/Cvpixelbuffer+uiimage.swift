//
//  CVPixelBuffer+UIImage.swift
//  SPAI
//

import UIKit

extension UIImage {
    /// Pixel dimensions of the underlying image, accounting for orientation.
    ///
    /// `size` is in points and already orientation-corrected, but detection boxes come back in
    /// pixels — so size checks have to compare against pixels or they are wrong by the scale
    /// factor on any image that came from a Retina screenshot or a modern camera.
    var pixelSize: (width: Int, height: Int) {
        guard let cg = cgImage else {
            return (Int(size.width * scale), Int(size.height * scale))
        }
        let rotated = imageOrientation == .left || imageOrientation == .right
            || imageOrientation == .leftMirrored || imageOrientation == .rightMirrored
        return rotated ? (cg.height, cg.width) : (cg.width, cg.height)
    }
}
import CoreImage
import CoreVideo

extension UIImage {
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
