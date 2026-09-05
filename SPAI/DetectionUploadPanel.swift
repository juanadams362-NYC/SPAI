//
//  DetectionUploadPanel.swift
//  SPAI
//

import SwiftUI

struct DetectionUploadPanel: View {
    let service: DetectionService
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("SIM TEST")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            Button {
                switch appModel.requestUploadToggle() {
                case .open:   openWindow(id: "upload")
                case .close:  dismissWindow(id: "upload")
                case .ignore: break
                }
            } label: {
                Label(appModel.isUploadWindowOpen ? "Close upload panel" : "Upload test media",
                      systemImage: appModel.isUploadWindowOpen ? "xmark.circle" : "photo.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityLabel("Upload test media")
            .accessibilityValue(appModel.isUploadWindowOpen ? "Open" : "Closed")
            .accessibilityHint("Give SPAI a photo or video to run detection against")
            .accessibilityAddTraits(appModel.isUploadWindowOpen ? [.isSelected] : [])

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
                if let tray = service.trayState?.capitalized {
                    Text("Tray: \(tray)\(service.instrumentCount.map { " (\($0))" } ?? "")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 260)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Test media upload")
    }
}
