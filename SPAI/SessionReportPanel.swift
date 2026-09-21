//  SessionReportPanel.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//
// All sizing is now proportional to panelWidth. Change panelWidth to update look everywhere.

import SwiftUI

struct SessionReportPanel: View {
    @Environment(AppModel.self) private var appModel
    var panelWidth: CGFloat = 350 // Default for previews and fallback

    private var passed: Bool { appModel.contaminationCount == 0 }

    private var duration: String {
        let seconds = Int(Date().timeIntervalSince(appModel.sessionStart))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var spacingL: CGFloat { panelWidth * 0.07 }
    private var spacingM: CGFloat { panelWidth * 0.02 }
    private var spacingS: CGFloat { panelWidth * 0.015 }

    private var fontLarge: CGFloat { panelWidth * 0.045 }
    private var fontMediumBold: CGFloat { panelWidth * 0.037 }
    private var fontSmall: CGFloat { panelWidth * 0.028 }
    private var fontTiny: CGFloat { panelWidth * 0.022 }

    var body: some View {
        VStack(alignment: .leading, spacing: spacingL) {
            HStack(spacing: spacingM) {
                Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: panelWidth * 0.097)) // originally 34 at 350 width ~ 0.097
                    .foregroundStyle(passed ? SPAIColor.safe : SPAIColor.critical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(passed ? "SESSION PASSED" : "SESSION FAILED")
                        .font(.system(size: fontMediumBold, weight: .bold, design: .monospaced))
                        .foregroundStyle(passed ? SPAIColor.safe : SPAIColor.critical)
                    Text("Compliance report")
                        .font(.system(size: fontSmall))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Divider().overlay(.white.opacity(0.2))

            reportRow(icon: "checklist", label: "Steps completed",
                      value: "\(SterileStep.allCases.count) of \(SterileStep.allCases.count)")
            reportRow(icon: "exclamationmark.triangle.fill", label: "Contamination events",
                      value: "\(appModel.contaminationCount)",
                      valueColor: passed ? .white : SPAIColor.critical)
            reportRow(icon: "clock.fill", label: "Session time", value: duration)

            Divider().overlay(.white.opacity(0.2))

            VStack(alignment: .leading, spacing: spacingS) {
                Text("EVENT HISTORY")
                    .font(.system(size: fontTiny, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appModel.eventLog) { event in
                            Text("\(event.timestamp)  \(event.message)")
                                .font(.system(size: fontTiny, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxHeight: panelWidth * 0.37) // 130 at 350 width ~ 0.37
            }

            HStack {
                Spacer()
                Button {
                    appModel.resetWorkflow()
                } label: {
                    Label("New Session", systemImage: "arrow.clockwise")
                        .font(.system(size: panelWidth * 0.04, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, spacingL)
                        .padding(.vertical, spacingS + 2)
                        .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                        .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
                }
                .buttonStyle(.plain)
//                .spaiHitTarget()
            }
            PanelDragHandle(panelID: "report")
        }
        .padding(spacingL)
        .frame(width: panelWidth)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session report. \(passed ? "Passed" : "Failed"). Duration \(duration). \(appModel.contaminationCount) contamination events.")
    }

    private func reportRow(icon: String, label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: fontSmall))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: fontMediumBold, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

#Preview {
    SessionReportPanel(panelWidth: 350)
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
