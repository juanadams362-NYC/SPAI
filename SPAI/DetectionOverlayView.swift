//
//  DetectionOverlayView.swift
//  SPAI
//
//  Renders the spatial workflow panels floating in the immersive space.
//  Each detection and guidance panel is a SwiftUI view turned into a
//  RealityKit attachment, positioned in 3D world space and billboarded
//  to face the user. Styled with the app tokens + animated LED borders.
//

import SwiftUI
import RealityKit

struct DetectionOverlayView: View {
    let detections: [Detection]

    var body: some View {
        RealityView { content, attachments in
            // Place each detection panel in world space.
            for detection in detections {
                if let panel = attachments.entity(for: detection.id) {
                    panel.position = detection.position
                    panel.components.set(BillboardComponent())
                    content.add(panel)
                }
            }

            // Place the guidance panel — the "what do I do now" panel —
            // centered and slightly closer so it reads as the primary guide.
            if let guidance = attachments.entity(for: "guidance") {
                guidance.position = SIMD3<Float>(0, 1.7, -0.9)
                guidance.components.set(BillboardComponent())
                content.add(guidance)
            }
        } attachments: {
            // One panel per detection.
            ForEach(detections) { detection in
                Attachment(id: detection.id) {
                    DetectionPanel(detection: detection)
                }
            }

            // The always-present guidance panel.
            Attachment(id: "guidance") {
                GuidancePanel()
            }
        }
    }
}

/// A detection panel — bigger and clearer than the old tiny label.
private struct DetectionPanel: View {
    let detection: Detection

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(spacing: 8) {
                Circle()
                    .fill(detection.status.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: detection.status.color, radius: 4)

                Text(detection.label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(detection.status.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(detection.status.color.opacity(0.8))
                    .clipShape(Capsule())
            }

            Text("\(Int(detection.confidence * 100))% confidence")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(SPAISpacing.m)
        .frame(width: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .ledBorder()
    }
}

/// The guidance panel — tells the user exactly where they are and what's next,
/// so they're never confused about what to do.
private struct GuidancePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("NEXT REQUIRED ACTION")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                Text("Current Step")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Decontamination")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Next Step")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                    Text("Inspection")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SPAIColor.accent)
            }

            Text("Start current step to begin processing.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .padding(SPAISpacing.s + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SPAIColor.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }
        .padding(SPAISpacing.l)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .ledBorder(lineWidth: 2.5)
    }
}
