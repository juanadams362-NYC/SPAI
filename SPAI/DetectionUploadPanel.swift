//
//  DetectionUploadPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/17/26.
//


//
//  DetectionUploadPanel.swift
//  SPAI
//
//  Simulator-only control: pick an image from the library and send it to
//  the backend /detect endpoint, so the detection pipeline can be tested
//  without the Vision Pro camera or a developer license. On hardware the
//  live camera feed replaces this.
//

import SwiftUI
import PhotosUI
import UIKit

struct DetectionUploadPanel: View {
    let service: DetectionService

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("SIM TEST")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Upload test image", systemImage: "photo.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
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
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await service.detect(image: image)
                }
            }
        }
    }
}