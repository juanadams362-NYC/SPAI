import SwiftUI
import AVFoundation

struct ContinuityCameraPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService
    @Environment(ContinuityCameraService.self) private var cameraService

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header
            preview
            detectionControls
            controls
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
    }

    private var header: some View {
        HStack {
            Text("IPHONE CAMERA")
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
                        .frame(width: w, height: h)
                        .clipped()
                }
                .frame(height: 180)
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
        HStack(spacing: SPAISpacing.m) {
            Button {
                cameraService.start()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            Button {
                cameraService.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.secondary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    ContinuityCameraPanel()
        .environment(AppModel())
        .environment(ContinuityCameraService())
        .padding(60)
        .background(.black)
}
