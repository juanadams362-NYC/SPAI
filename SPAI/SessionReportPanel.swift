//  SessionReportPanel.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//  End-of-session compliance report. Appears when the last workflow
//  step completes — the session's receipt. Pass means zero
//  contamination events, fail means the log tells the story.
//

import SwiftUI

struct SessionReportPanel: View {
    @Environment(AppModel.self) private var appModel

    private var passed: Bool { appModel.contaminationCount == 0 }

    private var duration: String {
        let seconds = Int(Date().timeIntervalSince(appModel.sessionStart))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            // Verdict up top, unmissable.
            HStack(spacing: SPAISpacing.m) {
                Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(passed ? SPAIColor.safe : SPAIColor.critical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(passed ? "SESSION PASSED" : "SESSION FAILED")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(passed ? SPAIColor.safe : SPAIColor.critical)
                    Text("Compliance report")
                        .font(.system(size: 12))
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

            // The event log is the evidence backing the verdict.
            VStack(alignment: .leading, spacing: SPAISpacing.s) {
                Text("EVENT HISTORY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appModel.eventLog) { event in
                            Text("\(event.timestamp)  \(event.message)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxHeight: 130)
            }

            HStack {
                Spacer()
                Button {
                    appModel.resetWorkflow()
                } label: {
                    Label("New Session", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, SPAISpacing.l)
                        .padding(.vertical, SPAISpacing.s + 2)
                        .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 420)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    private func reportRow(icon: String, label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

#Preview {
    SessionReportPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
