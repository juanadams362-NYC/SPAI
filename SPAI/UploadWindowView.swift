//
//  UploadWindowView.swift
//  SPAI
//
//  Created by Juan Adams on 6/18/26.
//

import SwiftUI
import PhotosUI
import UIKit
import AVKit
import UniformTypeIdentifiers

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("spai_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

struct UploadWindowView: View {
    @Environment(DetectionService.self) private var service
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var videoService = VideoFrameService()
    @State private var player: AVPlayer?
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var videoDuration: Double = 0
    @State private var loadError: String?
    @State private var isLoadingMedia = false
    @State private var lastVideoDetectionState: String?
    @State private var isFileImporterPresented = false

    // Batch testing mode for simulator
    @State private var batchImages: [UIImage] = []
    @State private var batchIndex: Int = 0
    @State private var batchTimer: Timer?
    @State private var isBatchMode: Bool = false
    @State private var showContinuityCamera: Bool = false

    var body: some View {
        VStack(spacing: SPAISpacing.m) {
            header

            if let videoURL {
                videoPreview(videoURL)
            } else if let image {
                imageWithBoxes(image)
            } else {
                placeholder
            }

            PhotosPicker(selection: $selectedItem,
                         matching: .any(of: [.images, .videos])) {
                Label(hasMedia ? "Choose another" : "Choose image or video",
                      systemImage: "photo.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Import from Files", systemImage: "folder.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.secondary.opacity(0.8), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            #if !targetEnvironment(simulator)
            Button {
                showContinuityCamera.toggle()
            } label: {
                Label(showContinuityCamera ? "Hide Camera" : "Use Live Camera", systemImage: "iphone.and.arrow.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.accent.opacity(0.6), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            if showContinuityCamera {
                Divider().padding(.vertical, SPAISpacing.s)
                ContinuityCameraMini()
            }
            #endif

            if isLoadingMedia {
                ProgressView("Loading media…")
            } else if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if service.isLoading {
                ProgressView("Detecting…")
            } else if videoURL != nil {
                videoSummary
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
            Task { await load(newItem) }
        }
        .onChange(of: appModel.isHalted) { _, isHalted in
            if isHalted {
                videoService.pauseForContamination()
            } else {
                videoService.resumeAfterContamination()
            }
        }
        .onDisappear {
            videoService.stop()
            // Same reasoning as SettingsView: catch the system close
            // button too, not just our own toggle path.
            appModel.isUploadWindowOpen = false
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.image, .movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await loadFromFileURL(url) }
            case .failure(let error):
                loadError = "Couldn't import file: \(error.localizedDescription)"
                print("[Upload] file import failed: \(error)")
            }
        }
    }

    private var hasMedia: Bool { image != nil || videoURL != nil }

    private func load(_ item: PhotosPickerItem) async {
        loadError = nil
        isLoadingMedia = true
        defer { isLoadingMedia = false }

        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        print("[Upload] picked item, types: \(item.supportedContentTypes.map(\.identifier)), isVideo: \(isVideo)")

        if isVideo {
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    loadError = "Video came back empty. If it's stored in iCloud it may still be downloading."
                    print("[Upload] movie transferable was nil")
                    return
                }
                image = nil
                videoURL = movie.url
                videoDuration = await duration(of: movie.url)
                lastVideoDetectionState = nil
                print("[Upload] video loaded: \(movie.url.lastPathComponent), \(videoDuration)s")
            } catch {
                loadError = "Couldn't load that video: \(error.localizedDescription)"
                print("[Upload] video load failed: \(error)")
            }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data) else {
                loadError = "Couldn't read that image."
                print("[Upload] image data was nil or undecodable")
                return
            }
            videoURL = nil
            videoDuration = 0
            image = ui
            lastVideoDetectionState = nil
            await service.detect(image: ui, step: SterileStep(rawValue: appModel.currentStepIndex))
        } catch {
            loadError = "Couldn't load that image: \(error.localizedDescription)"
            print("[Upload] image load failed: \(error)")
        }
    }

    private func loadFromFileURL(_ url: URL) async {
        loadError = nil
        isLoadingMedia = true
        defer { isLoadingMedia = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension
        let type = UTType(filenameExtension: ext)

        do {
            if type?.conforms(to: .movie) == true {
                let destExt = ext.isEmpty ? "mov" : ext
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spai_\(UUID().uuidString)")
                    .appendingPathExtension(destExt)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)

                image = nil
                videoURL = dest
                videoDuration = await duration(of: dest)
                lastVideoDetectionState = nil
                print("[Upload] video imported: \(dest.lastPathComponent), \(videoDuration)s")
                return
            }

            if type?.conforms(to: .image) == true {
                let data = try Data(contentsOf: url)
                guard let ui = UIImage(data: data) else {
                    loadError = "Couldn't read that image."
                    print("[Upload] file image data undecodable: \(url)")
                    return
                }
                videoURL = nil
                videoDuration = 0
                image = ui
                lastVideoDetectionState = nil
                await service.detect(image: ui, step: SterileStep(rawValue: appModel.currentStepIndex))
                print("[Upload] image imported: \(url.lastPathComponent)")
                return
            }

            // Fallback: try image first, then treat as video
            if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                videoURL = nil
                videoDuration = 0
                image = ui
                lastVideoDetectionState = nil
                await service.detect(image: ui, step: SterileStep(rawValue: appModel.currentStepIndex))
                print("[Upload] image imported via fallback: \(url.lastPathComponent)")
            } else {
                let destExt = ext.isEmpty ? "mov" : ext
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spai_\(UUID().uuidString)")
                    .appendingPathExtension(destExt)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)

                image = nil
                videoURL = dest
                videoDuration = await duration(of: dest)
                lastVideoDetectionState = nil
                print("[Upload] video imported via fallback: \(dest.lastPathComponent), \(videoDuration)s")
            }
        } catch {
            loadError = "Couldn't import that file: \(error.localizedDescription)"
            print("[Upload] file import processing failed: \(error)")
        }
    }

    private func runVideo() {
        guard let videoURL else { return }
        if player == nil { player = AVPlayer(url: videoURL) }
        guard let player else { return }
        lastVideoDetectionState = nil

        videoService.onFrame = { frame in
            await service.detect(
                image: frame,
                step: SterileStep(rawValue: appModel.currentStepIndex),
                preferOnDevice: shouldPreferOnDeviceForVideo
            )
            logVideoDetectionTransitionIfNeeded()
        }
        player.isMuted = true
        Task {
            await videoService.start(url: videoURL, player: player, interval: 1.0)
        }
    }

    private func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds,
              seconds.isFinite else { return 0 }
        return seconds
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Detection").font(.title2.bold())
                Text("Upload images/videos or use live camera")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismissWindow(id: "upload")
                appModel.isUploadWindowOpen = false
            } label: {
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
                    Text("Choose an image or video to run detection")
                }
                .foregroundStyle(.secondary)
            }
    }

    private func videoPreview(_ url: URL) -> some View {
        VideoPlayer(player: player)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
            }
    }

    private var videoSummary: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(spacing: 8) {
                Image(systemName: "film")
                Text("Video loaded")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1fs", videoDuration))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            if videoService.isRunning {
                HStack(spacing: SPAISpacing.s) {
                    ProgressView().controlSize(.small)
                    Text(String(format: "%.1fs · %d frames · %d skipped", videoService.currentTime, videoService.framesProcessed, videoService.framesSkipped))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        videoService.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, SPAISpacing.m)
                            .padding(.vertical, SPAISpacing.xs)
                            .background(SPAIColor.critical, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    runVideo()
                } label: {
                    Label("Run detection on video", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPAISpacing.s + 2)
                        .background(SPAIColor.safe, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)

                if videoService.framesProcessed > 0 {
                    Text("\(videoService.framesProcessed) frames processed, \(videoService.framesSkipped) skipped. Watch the detection and workflow panels.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldPreferOnDeviceForVideo: Bool {
        videoService.isLongVideo() || videoDuration >= 60
    }

    private func logVideoDetectionTransitionIfNeeded() {
        let state = currentVideoDetectionState
        guard state != lastVideoDetectionState else { return }
        lastVideoDetectionState = state

        appModel.logVideoDetectionTransition(state, at: videoService.currentTime)
        videoService.logStateTransition(state: state, at: videoService.currentTime)
    }

    private var currentVideoDetectionState: String {
        let hasHand = service.detections.contains {
            DetectionService.isHandClass($0.className)
        }
        let hasGlove = service.detections.contains {
            DetectionService.isGloveClass($0.className)
        }

        if hasHand && !hasGlove { return "bare hand" }
        if hasGlove && !hasHand { return "gloves on" }
        if service.trayState == "loaded" { return "tray loaded" }
        if service.hasInstrumentDetection { return "instruments visible" }
        return "no detection"
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

// MARK: - Continuity Camera Mini Component

struct ContinuityCameraMini: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @Environment(ContinuityCameraService.self) private var cameraService

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            HStack {
                Text("LIVE CAMERA")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(cameraService.status.label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(cameraService.status.color)
            }

            ZStack {
                RoundedRectangle(cornerRadius: SPAIRadius.small)
                    .fill(.white.opacity(0.05))
                    .frame(height: 140)

                if let img = cameraService.latestImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.small))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Waiting for device...")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            HStack(spacing: SPAISpacing.s) {
                Button {
                    cameraService.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPAISpacing.xs + 2)
                        .background(SPAIColor.safe, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)

                Button {
                    cameraService.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPAISpacing.xs + 2)
                        .background(SPAIColor.critical, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
            }

            Toggle(isOn: Binding(
                get: { cameraService.detectionEnabled },
                set: { cameraService.detectionEnabled = $0 }
            )) {
                Text("Run detection on feed")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .toggleStyle(.switch)
            .tint(SPAIColor.primary)
        }
        .padding(SPAISpacing.m)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .onAppear {
            cameraService.onFrameForDetection = { ui in
                await detectionService.detect(
                    image: ui,
                    step: SterileStep(rawValue: appModel.currentStepIndex),
                    preferOnDevice: false
                )
            }
        }
        .onDisappear {
            cameraService.detectionEnabled = false
            cameraService.stop()
        }
    }
}
