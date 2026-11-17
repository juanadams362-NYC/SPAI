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
            PanelHeader("Test Media", icon: "photo.on.rectangle.angled", tint: SPAIColor.secondary)

            Button {
                if appModel.isUploadWindowOpen {
                    dismissWindow(id: "upload")
                    appModel.isUploadWindowOpen = false
                } else {
                    openWindow(id: "upload")
                    appModel.isUploadWindowOpen = true
                }
            } label: {
                Label(appModel.isUploadWindowOpen ? "Close upload panel" : "Upload test media",
                      systemImage: appModel.isUploadWindowOpen ? "xmark.circle" : "photo.badge.plus")
            }
            .buttonStyle(.spai(appModel.isUploadWindowOpen ? .glass : .tinted(SPAIColor.secondary), fullWidth: true))

            if service.isLoading {
                HStack(spacing: 10) {
                    TypingDots(color: SPAIColor.primaryBright)
                    Text("Detecting…")
                        .font(SPAIFont.caption)
                        .foregroundStyle(SPAIText.secondary)
                }
            } else if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if service.hasResult {
                Label(service.detections.count == 1 ? "1 thing detected" : "\(service.detections.count) things detected",
                      systemImage: "viewfinder")
                    .font(SPAIFont.caption.weight(.semibold))
                    .foregroundStyle(SPAIText.secondary)
                if let tray = service.trayState?.capitalized {
                    Label("Tray: \(tray)\(service.instrumentCount.map { " (\($0))" } ?? "")",
                          systemImage: tray.lowercased() == "loaded" ? "tray.full.fill" : "tray")
                        .font(SPAIFont.caption.weight(.semibold))
                        .foregroundStyle(tray.lowercased() == "loaded" ? SPAIColor.safe : SPAIText.secondary)
                }
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 280)
        .spaiPanel(PanelID.upload)
    }
}
