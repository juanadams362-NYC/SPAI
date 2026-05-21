//
//  Detection.swift
//  SPAI
//
//  Created by Juan Adams on 5/20/26.
//  Represents one object the AI detected in 3D space.
//  Used by DetectionOverlayView to render floating boxes + lables.
//


import Foundation
import SwiftUI

/// A single AI detection. In stub mode hardcoded.
/// Once backend is wired up, / detect responces gets parsed into this.
struct Detection: Identifiable {
    let id = UUID()
    let label: String           // "glove", "hand", "tray", etc.
    let confidence: Float       // 0.0 to 1.0
    let position: SIMD3<Float>  // 3D world position (meters)
    let size: SIMD3<Float>      // width, height, depth in meters
    let status: DetectionStatus
}

/// Sample detections placed roughly in front of the user. Hardcoded later will be replaced by parsed /detect output.
extension Detection {
    static let sampleDetections: [Detection] = [
        Detection(
            label: "glove",
            confidence: 0.94,
            position: SIMD3<Float>(-0.3, 1.4, -1.0),    // left, eye-height, 1m forward
            size: SIMD3<Float>(0.18, 0.12, 0.05),
            status: DetectionStatus.safe
        ),
        Detection(
            label: "Hand",
            confidence: 0.80,
            position: SIMD3<Float>(0.3, 1.4, -1.0),   // right, eye-height
            size: SIMD3<Float>(0.16, 0.14, 0.05),
            status: DetectionStatus.safe
        ),
        Detection(
            label: "Contamination Risk",
            confidence: 0.76,
            position: SIMD3<Float>(0.0, 1.1, -1.2),
            size: SIMD3<Float>(0.22, 0.15, 0.05),
            status: DetectionStatus.warning
        ),
    ]
    
}
