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
    /// Shared CIContext for all pixel-buffer conversions. Creating one per frame is expensive;
    /// a shared instance reuses GPU resources across calls.
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    static func from(readOnlyBuffer: CVReadOnlyPixelBuffer) -> UIImage? {
        readOnlyBuffer.withUnsafeBuffer { pixelBuffer -> UIImage? in
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
    }

    /// Converts a pixel buffer to UIImage, simultaneously cropping to the detection zone
    /// defined in DetectionTuning.
    ///
    /// Using CIImage for the crop avoids decoding the full frame before discarding the edges —
    /// `ciImage.cropped(to:)` is lazy; pixels outside the rect are never rendered.
    ///
    /// CIImage uses a bottom-left coordinate origin, so the vertical-offset direction is
    /// inverted relative to UIKit: positive `detectionZoneVerticalOffset` shifts the zone
    /// toward lower Y values, which is toward the bottom of the real-world scene.
    static func fromZoneCropped(readOnlyBuffer: CVReadOnlyPixelBuffer) -> UIImage? {
        readOnlyBuffer.withUnsafeBuffer { pixelBuffer -> UIImage? in
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let full = ciImage.extent

            let zoneW = full.width  * CGFloat(DetectionTuning.detectionZoneWidthFraction)
            let zoneH = full.height * CGFloat(DetectionTuning.detectionZoneHeightFraction)
            let originX = (full.width  - zoneW) / 2
            // CIImage Y grows upward; positive offset shifts the zone toward the bottom
            // of the real scene (the bench), which is the low-Y half of the buffer.
            let originY = (full.height - zoneH) / 2
                - full.height * CGFloat(DetectionTuning.detectionZoneVerticalOffset)

            let cropRect = CGRect(x: originX, y: originY, width: zoneW, height: zoneH)
                .intersection(full)
            guard cropRect.width > 0, cropRect.height > 0 else { return nil }

            let cropped = ciImage.cropped(to: cropRect)
            guard let cgImage = sharedCIContext.createCGImage(cropped, from: cropped.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }
    }

    /// Returns a copy of this image cropped to the detection zone defined in DetectionTuning.
    ///
    /// Used for the video-playback path where frames arrive as UIImage (already decoded).
    /// UIKit uses a top-left coordinate origin, so positive `detectionZoneVerticalOffset`
    /// increases `originY`, which shifts the zone downward — toward the bench.
    func croppedToDetectionZone() -> UIImage {
        let w = size.width
        let h = size.height
        let zoneW = w * CGFloat(DetectionTuning.detectionZoneWidthFraction)
        let zoneH = h * CGFloat(DetectionTuning.detectionZoneHeightFraction)
        let originX = (w - zoneW) / 2
        let originY = (h - zoneH) / 2
            + h * CGFloat(DetectionTuning.detectionZoneVerticalOffset)
        let cropRect = CGRect(x: originX, y: originY, width: zoneW, height: zoneH)
            .integral
            .intersection(CGRect(origin: .zero, size: size))
        guard cropRect.width > 0, cropRect.height > 0 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: cropRect.size, format: format).image { _ in
            draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
    }
}
