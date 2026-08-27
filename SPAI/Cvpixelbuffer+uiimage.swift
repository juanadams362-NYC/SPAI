//
//  CVPixelBuffer+UIImage.swift
//  SPAI
//

import UIKit
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
