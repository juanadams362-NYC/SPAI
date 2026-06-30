//
//  DetectionUploadPanel.swift
//  SPAI
//
//  Sim-only launcher. The picker can't live in the immersive space
//  (PhotosPicker presents a sheet, which visionOS won't show inside an
//  ImmersiveSpace), so this just opens the upload window and shows the
//  latest result here.
//

import SwiftUI

struct DetectionUploadPanel: View {
    let service: DetectionService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("SIM TEST")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            Button { openWindow(id: "upload") } label: {
                Label("Upload test image", systemImage: "photo.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            if service.isLoading {
                Text("Detecting…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            } else if let error = service.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if service.hasResult {
                Text("\(service.detections.count) detection(s)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }
}
