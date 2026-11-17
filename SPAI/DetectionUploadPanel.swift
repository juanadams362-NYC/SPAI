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
            PanelHeader("Test Detection", icon: "photo.on.rectangle.angled", tint: SPAIColor.secondary)

            Button {
                if appModel.isUploadWindowOpen {
                    dismissWindow(id: "upload")
                    appModel.isUploadWindowOpen = false
                } else {
                    openWindow(id: "upload")
                    appModel.isUploadWindowOpen = true
                }
            } label: {
                Label(appModel.isUploadWindowOpen ? "Close test window" : "Open test media",
                      systemImage: appModel.isUploadWindowOpen ? "xmark.circle" : "photo.badge.plus")
            }
            .buttonStyle(.spai(appModel.isUploadWindowOpen ? .glass : .tinted(SPAIColor.secondary), fullWidth: true))

            status
        }
        .padding(SPAISpacing.l)
        .frame(width: 280)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    @ViewBuilder
    private var status: some View {
        if service.isLoading {
            HStack(spacing: 10) {
                TypingDots(color: SPAIColor.primaryBright)
                Text("Detecting…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SPAIColor.textSecondary)
            }
        } else if let error = service.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SPAIColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if service.hasResult {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(service.detections.count) detection\(service.detections.count == 1 ? "" : "s")",
                      systemImage: "viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SPAIColor.textSecondary)
                if let tray = service.trayState?.capitalized {
                    Label("Tray: \(tray)\(service.instrumentCount.map { " (\($0))" } ?? "")",
                          systemImage: tray.lowercased() == "loaded" ? "tray.full.fill" : "tray")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tray.lowercased() == "loaded" ? SPAIColor.safe : SPAIColor.textSecondary)
                }
            }
        } else {
            Text("Run detection on photos, videos or a live iPhone camera.")
                .font(.system(size: 12))
                .foregroundStyle(SPAIColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
