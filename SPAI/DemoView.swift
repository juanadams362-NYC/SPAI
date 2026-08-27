//
//  DemoView.swift
//  SPAI
//

import SwiftUI
import PhotosUI

struct DemoView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var detections: [BackendDetection] = []
    @State private var mode: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let client = BackendClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SPAISpacing.l) {
                    if let image {
                        imageWithBoxes(image)
                    } else {
                        placeholder
                    }

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Choose Image", systemImage: "photo")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SPAIColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
                    }

                    if image != nil {
                        Button {
                            Task { await runDetection() }
                        } label: {
                            Label(isLoading ? "Detecting..." : "Run Detection",
                                  systemImage: "viewfinder")
                                .font(.headline)
                                .foregroundStyle(SPAIColor.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(SPAIColor.primary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
                        }
                        .disabled(isLoading)
                    }

                    if !detections.isEmpty {
                        resultsSummary
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(SPAIColor.critical)
                    }
                }
                .padding()
            }
            .navigationTitle("SPAI Detection Demo")
            .onChange(of: selectedItem) { _, newItem in
                Task { await loadImage(from: newItem) }
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: SPAIRadius.large)
            .fill(SPAIColor.neutralMid.opacity(0.3))
            .frame(height: 300)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundStyle(SPAIColor.neutralMid)
                    Text("Choose an image to detect")
                        .foregroundStyle(SPAIColor.neutralMid)
                }
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

                ForEach(detections) { det in
                    let x = CGFloat(det.box[0]) * scale
                    let y = CGFloat(det.box[1]) * scale
                    let w = CGFloat(det.box[2] - det.box[0]) * scale
                    let h = CGFloat(det.box[3] - det.box[1]) * scale

                    Rectangle()
                        .stroke(boxColor(det.className), lineWidth: 2)
                        .frame(width: w, height: h)
                        .overlay(alignment: .topLeading) {
                            Text("\(det.className) \(Int(det.confidence * 100))%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(boxColor(det.className))
                                .offset(y: -20)
                        }
                        .offset(x: x, y: y)
                }
            }
            .frame(width: displayWidth, height: displayHeight)
        }
        .aspectRatio(
            image.map { $0.size.width / $0.size.height } ?? 1,
            contentMode: .fit
        )
    }

    private var resultsSummary: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text("Found \(detections.count) object\(detections.count == 1 ? "" : "s")")
                .font(.headline)
            Text("Mode: \(mode)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(detections) { det in
                HStack {
                    Circle()
                        .fill(boxColor(det.className))
                        .frame(width: 10, height: 10)
                    Text(det.className)
                    Spacer()
                    Text("\(Int(det.confidence * 100))%")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SPAIColor.neutralLight.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
    }

    private func boxColor(_ className: String) -> Color {
        switch className {
        case "glove": return SPAIColor.primary
        case "hand":  return SPAIColor.accent
        default:      return SPAIColor.warning
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        detections = []
        errorMessage = nil
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            image = uiImage
        }
    }

    private func runDetection() async {
        guard let image else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.detect(image: image)
            detections = response.detections
            mode = response.mode
        } catch {
            errorMessage = "Detection failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DemoView()
}
