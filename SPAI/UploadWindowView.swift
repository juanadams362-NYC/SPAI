//
//  UploadWindowView.swift
//  SPAI
//
//  Created by Juan Adams on 6/18/26.
//

import SwiftUI
import PhotosUI
import UIKit

struct UploadWindowView: View {
    @Environment(DetectionService.self) private var service
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: SPAISpacing.m) {
            header

            if let image {
                imageWithBoxes(image)
            } else {
                placeholder
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(image == nil ? "Choose image" : "Choose another",
                      systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)

            if service.isLoading {
                ProgressView("Detecting…")
            } else if service.hasResult {
                resultSummary
            } else if let error = service.errorMessage {
                Text(error).foregroundStyle(SPAIColor.warning)
            }

            Spacer()
        }
        .padding(SPAISpacing.l)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    image = ui
                    await service.detect(image: ui, step: SterileStep(rawValue: appModel.currentStepIndex))
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Detection Test").font(.title2.bold())
                Text("Sim-only · feeds the live detection panel")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismissWindow(id: "upload") } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: SPAIRadius.medium)
            .fill(SPAIColor.neutralMid.opacity(0.2))
            .frame(height: 220)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40))
                    Text("Choose an image to run detection")
                }
                .foregroundStyle(.secondary)
            }
    }

    private func imageWithBoxes(_ uiImage: UIImage) -> some View {
        GeometryReader { geo in
            let displayWidth = geo.size.width
            let scale = displayWidth / uiImage.size.width
            let displayHeight = uiImage.size.height * scale

            ZStack(alignment: .topLeading) {
                Image(uiImage: uiImage)
                    .resizable()
                    .frame(width: displayWidth, height: displayHeight)

                ForEach(service.detections) { det in
                    let x = CGFloat(det.box[0]) * scale
                    let y = CGFloat(det.box[1]) * scale
                    let w = CGFloat(det.box[2] - det.box[0]) * scale
                    let h = CGFloat(det.box[3] - det.box[1]) * scale

                    Rectangle()
                        .stroke(boxColor(det.className), lineWidth: 1.5)
                        .frame(width: w, height: h)
                        .overlay(alignment: .topLeading) {
                            Text("\(det.className) \(Int(det.confidence * 100))%")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(boxColor(det.className).opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .offset(y: -16)
                        }
                        .offset(x: x, y: y)
                }
            }
            .frame(width: displayWidth, height: displayHeight)
        }
        .aspectRatio(uiImage.size.width / uiImage.size.height, contentMode: .fit)
    }

    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.xs) {
            Text("Found \(service.detections.count) object\(service.detections.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
            if let tray = service.trayState?.capitalized {
                HStack(spacing: 8) {
                    Image(systemName: tray.lowercased() == "loaded" ? "tray.full" : "tray")
                        .foregroundStyle(.white)
                    Text("Tray: \(tray)")
                        .font(.subheadline.weight(.semibold))
                    if let count = service.instrumentCount {
                        Text("(\(count))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(service.detections) { det in
                HStack {
                    Circle().fill(boxColor(det.className)).frame(width: 10, height: 10)
                    Text(det.className)
                    Spacer()
                    Text("\(Int(det.confidence * 100))%").foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func boxColor(_ className: String) -> Color {
        switch className.lowercased() {
        case "glove": return SPAIColor.primary
        case "hand":  return SPAIColor.accent
        default:      return SPAIColor.warning
        }
    }
}

