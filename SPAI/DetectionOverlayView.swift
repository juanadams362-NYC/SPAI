//
//  DetectionOverlayView.swift
//  SPAI
//
//  Created by Juan Adams on 5/21/26.
//
//  Renders 3D detection labels floating in the immersive space.
//  One frosted glass card per detection, positioned in world space.
//  Lives inside the ImmersiveSpace, layered over passthrough.
//

import SwiftUI
import RealityKit

struct DetectionOverlayView: View {
    let detections: [Detection]
    
    var body: some View {
        // RealityView is the bridge SwiftUI and 3D content.
        // The 'attachments' closure declares SwiftUI views that can be placed in 3D spaces as RealityKit entities.
        RealityView { content, attachments in
            for detection in detections {
                // Find the SwiftUI attachment for the detection by id.
                if let label = attachments.entity(for: detection.id){
                    // Place the label in the 3D world space.
                    label.position = detection.position
                    // Make sure it always faces the user (billboard behavior).
                    label.components.set(BillboardComponent())
                    content.add(label)
                }
            }
        } attachments: {
            // Declare one SwiiftUI view per detection. RealityKit will convert each into a 3D entity I can position in space.
            ForEach(detections) { detection in
                Attachment(id: detection.id){
                    DetectionLabel(detection: detection)
                }
            }
        }
    }
}

/// Floating glass card
private struct DetectionLabel: View {
    let detection: Detection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: status dot + label
            HStack(spacing: 6) {
                Circle()
                    .fill(detection.status.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: detection.status.color, radius: 4)
                
                Text(detection.label)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
            }
            
            // Confidence reading
                Text("\(Int(detection.confidence * 100))% confidence")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            // Frosted glass. RealityKit honors .regularMaterial in 3D.
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            // Subtle colored border that matches the status.
            RoundedRectangle(cornerRadius: 12)
                .stroke(detection.status.color.opacity(0.5), lineWidth: 1)
        )
        // Faint outer glow tinted by status color.
        .shadow(color: detection.status.color.opacity(0.3), radius: 8)
    }
}
