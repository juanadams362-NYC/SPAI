import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ContinuityCameraPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @Environment(ContinuityCameraService.self) private var cameraService
    
    #if targetEnvironment(simulator)
    @State private var showingImagePicker = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header
            preview
            detectionControls
            controls
            
            #if targetEnvironment(simulator)
            simulatorControls
            #endif
        }
        .padding(SPAISpacing.l)
        .frame(width: 360)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
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
        }
        #if targetEnvironment(simulator)
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    cameraService.testImageURL = url
                }
            }
        }
        #endif
    }

    private var header: some View {
        HStack {
            Text("CONTINUITY CAMERA")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(cameraService.status.label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(cameraService.status.color)
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SPAIRadius.medium)
                .fill(.white.opacity(0.05))
                .frame(height: 180)

            if let img = cameraService.latestImage {
                GeometryReader { geo in
                    let w = geo.size.width
                    let scale = w / img.size.width
                    let h = img.size.height * scale
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("No preview")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var detectionControls: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Toggle(isOn: Binding(get: { cameraService.detectionEnabled }, set: { cameraService.detectionEnabled = $0 })) {
                Label("Detect on Live Feed", systemImage: cameraService.detectionEnabled ? "viewfinder.circle.fill" : "viewfinder")
            }
            .toggleStyle(.switch)
            .font(.system(size: 13))
            .foregroundStyle(.white)

            HStack(spacing: SPAISpacing.s) {
                Text("Sample every")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                Text(String(format: "%.1fs", cameraService.detectionInterval))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Stepper(value: Binding(get: { cameraService.detectionInterval }, set: { cameraService.detectionInterval = max(0.3, min(3.0, $0)) }), in: 0.3...3.0, step: 0.1) {
                    EmptyView()
                }
                .labelsHidden()
            }
        }
    }

    private var controls: some View {
        HStack(spacing: SPAISpacing.s) {
            Button {
                cameraService.start()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()

            Button {
                cameraService.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.secondary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
        }
    }
    
    #if targetEnvironment(simulator)
    private var simulatorControls: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Divider()
            
            Text("SIMULATOR TESTING")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.6))
            
            Button {
                showingImagePicker = true
            } label: {
                Label("Load Test Image", systemImage: "photo.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SPAISpacing.s)
                    .background(SPAIColor.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            
            Text("Tip: Take a photo on your iPhone, AirDrop it to your Mac, then load it here")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif
}

#Preview {
    ContinuityCameraPanel()
        .environment(AppModel())
        .environment(DetectionService())
        .environment(ContinuityCameraService())
        .padding(60)
        .background(.black)
}
