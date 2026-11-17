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

            Group {
                if let videoURL {
                    videoPreview(videoURL)
                } else if let image {
                    imageWithBoxes(image)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem,
                             matching: .any(of: [.images, .videos])) {
                    Label(hasMedia ? "Choose another" : "Photos", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.spai(.primary, fullWidth: true))

                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Files", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.spai(.glass, fullWidth: true))
            }

            #if !targetEnvironment(simulator)
            Button {
                withAnimation(.snappy) { showContinuityCamera.toggle() }
            } label: {
                Label(showContinuityCamera ? "Hide Live Camera" : "Use Live iPhone Camera",
                      systemImage: "iphone.and.arrow.forward")
            }
            .buttonStyle(.spai(.tinted(SPAIColor.accent), fullWidth: true))

            if showContinuityCamera {
                ContinuityCameraMini()
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top)))
            }
            #endif

            Group {
                if isLoadingMedia {
                    statusLine(text: "Loading media…", tint: SPAIColor.primaryBright, busy: true)
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SPAIColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if service.isLoading {
                    statusLine(text: "Detecting…", tint: SPAIColor.primaryBright, busy: true)
                } else if videoURL != nil {
                    videoSummary
                } else if service.hasResult {
                    resultSummary
                } else if let error = service.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SPAIColor.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(SPAISpacing.l)
        .frame(width: 520)
        .frame(minHeight: 600)
        .spaiWindowBackground(cornerRadius: 36, aurora: false)
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

    private func statusLine(text: String, tint: Color, busy: Bool) -> some View {
        HStack(spacing: 10) {
            if busy {
                TypingDots(color: tint)
            }
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SPAIColor.textSecondary)
            Spacer()
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
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SPAIColor.onFill)
                .frame(width: 42, height: 42)
                .background(SPAIGradient.ai, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: SPAIColor.secondary.opacity(0.45), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Detection")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text("Run SPAI on photos, videos or a live camera")
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.textTertiary)
            }
            Spacer()
            Button {
                dismissWindow(id: "upload")
                appModel.isUploadWindowOpen = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.spaiIcon(tint: .white, size: 40))
            .accessibilityLabel("Close")
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
            .fill(SPAIColor.surface)
            .frame(height: 230)
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                    .strokeBorder(SPAIColor.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
            }
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(SPAIColor.primaryBright)
                    Text("Choose an image or video to run detection")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SPAIColor.textSecondary)
                    HStack(spacing: 14) {
                        legendDot("Glove", SPAIColor.safe)
                        legendDot("Bare hand", SPAIColor.critical)
                        legendDot("Instrument", SPAIColor.primary)
                    }
                }
            }
    }

    private func legendDot(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SPAIColor.textTertiary)
        }
    }

    private func videoPreview(_ url: URL) -> some View {
        VideoPlayer(player: player)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
            }
    }

    private var videoSummary: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .foregroundStyle(SPAIColor.accent)
                Text("Video loaded")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Spacer()
                Text(String(format: "%.1fs", videoDuration))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SPAIColor.textTertiary)
            }

            if videoService.isRunning {
                HStack(spacing: SPAISpacing.s) {
                    LiveDot(color: SPAIColor.critical, size: 7)
                    Text(String(format: "%.1fs · %d frames · %d skipped", videoService.currentTime, videoService.framesProcessed, videoService.framesSkipped))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(SPAIColor.textSecondary)
                    Spacer()
                    Button {
                        videoService.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.spai(.tinted(SPAIColor.critical), size: .small))
                }
            } else {
                Button {
                    runVideo()
                } label: {
                    Label("Run detection on video", systemImage: "play.fill")
                }
                .buttonStyle(.spai(.success, fullWidth: true))

                if videoService.framesProcessed > 0 {
                    Text("\(videoService.framesProcessed) frames processed, \(videoService.framesSkipped) skipped. Watch the detection and workflow panels.")
                        .font(.system(size: 12))
                        .foregroundStyle(SPAIColor.textTertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
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
                    let color = boxColor(det.className)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(color, lineWidth: 2)
                        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .frame(width: w, height: h)
                        .shadow(color: color.opacity(0.7), radius: 4)
                        .overlay(alignment: .topLeading) {
                            Text("\(det.className) \(Int(det.confidence * 100))%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(SPAIColor.onFill)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .fixedSize()
                                .offset(y: -18)
                        }
                        .offset(x: x, y: y)
                }
            }
            .frame(width: displayWidth, height: displayHeight)
        }
        .aspectRatio(uiImage.size.width / uiImage.size.height, contentMode: .fit)
    }

    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Found \(service.detections.count) object\(service.detections.count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Spacer()
                if let tray = service.trayState?.capitalized {
                    SPAIChip(text: "Tray: \(tray)\(service.instrumentCount.map { " (\($0))" } ?? "")",
                             icon: tray.lowercased() == "loaded" ? "tray.full.fill" : "tray",
                             tint: tray.lowercased() == "loaded" ? SPAIColor.safe : Color.white.opacity(0.75))
                }
            }
            ForEach(service.detections) { det in
                HStack(spacing: 10) {
                    Circle().fill(boxColor(det.className)).frame(width: 9, height: 9)
                    Text(det.className)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SPAIColor.textPrimary)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .leading)
                    ConfidenceBar(value: det.confidence, color: boxColor(det.className))
                    Text("\(Int(det.confidence * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(SPAIColor.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
    }

    /// Box colors carry meaning: green = gloved, rose = bare hand, cyan = instrument.
    private func boxColor(_ className: String) -> Color {
        if DetectionService.isGloveClass(className) { return SPAIColor.safe }
        if DetectionService.isHandClass(className) { return SPAIColor.critical }
        return SPAIColor.primary
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
                HStack(spacing: 6) {
                    LiveDot(color: cameraService.status.color, size: 6, animating: cameraService.isRunning)
                        .id(cameraService.isRunning)
                    Text("Live camera")
                        .spaiEyebrow()
                }
                Spacer()
                Text(cameraService.status.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(cameraService.status.color)
                    .lineLimit(1)
            }

            ZStack {
                RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .frame(height: 150)

                if let img = cameraService.latestImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 28))
                            .foregroundStyle(SPAIColor.textTertiary)
                            .symbolEffect(.pulse)
                        Text("Waiting for device…")
                            .font(.system(size: 12))
                            .foregroundStyle(SPAIColor.textTertiary)
                    }
                }
            }

            HStack(spacing: SPAISpacing.s) {
                Button {
                    cameraService.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.spai(.success, size: .small, fullWidth: true))

                Button {
                    cameraService.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.spai(.tinted(SPAIColor.critical), size: .small, fullWidth: true))
            }

            Toggle(isOn: Binding(
                get: { cameraService.detectionEnabled },
                set: { cameraService.detectionEnabled = $0 }
            )) {
                Text("Run detection on feed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SPAIColor.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(SPAIColor.primary)
        }
        .padding(SPAISpacing.m)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
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
