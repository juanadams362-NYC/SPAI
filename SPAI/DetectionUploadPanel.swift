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
            Text("TEST MEDIA").spaiEyebrow()

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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, SPAISpacing.l)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()

            if service.isLoading {
                Text("Detecting…")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.secondary)
            } else if let error = service.errorMessage {
                Text(error)
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if service.hasResult {
                Text(service.detections.count == 1 ? "1 thing detected" : "\(service.detections.count) things detected")
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.secondary)
                if let tray = service.trayState?.capitalized {
                    Text("Tray: \(tray)\(service.instrumentCount.map { " (\($0))" } ?? "")")
                        .font(SPAIFont.caption)
                        .foregroundStyle(SPAIText.secondary)
                }
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 260)
        .spaiPanel(PanelID.upload)
    }
}
