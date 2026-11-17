//  SessionReportPanel.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//

import SwiftUI

struct SessionReportPanel: View {
    @Environment(AppModel.self) private var appModel

    @State private var celebrate = false

    private var passed: Bool { appModel.contaminationCount == 0 }
    private var tint: Color { passed ? SPAIColor.safe : SPAIColor.critical }

    private var duration: String {
        let seconds = Int(Date().timeIntervalSince(appModel.sessionStart))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(spacing: SPAISpacing.l) {
            hero

            HStack(spacing: 10) {
                MetricTile(label: "Stations",
                           value: "\(SterileStep.allCases.count)/\(SterileStep.allCases.count)",
                           icon: "checklist", tint: SPAIColor.primary)
                MetricTile(label: "Contamination",
                           value: "\(appModel.contaminationCount)",
                           icon: "exclamationmark.triangle.fill",
                           tint: passed ? SPAIColor.safe : SPAIColor.critical,
                           valueColor: passed ? SPAIColor.textPrimary : SPAIColor.critical)
                MetricTile(label: "Time", value: duration, icon: "clock.fill", tint: SPAIColor.accent)
            }

            VStack(alignment: .leading, spacing: SPAISpacing.s) {
                Text("Event history")
                    .spaiEyebrow()

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(appModel.eventLog) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(event.kind.color)
                                    .frame(width: 6, height: 6)
                                Text(event.timestamp)
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(SPAIColor.textTertiary)
                                Text(event.message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(SPAIColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 130)
                .padding(12)
                .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
            }

            Button {
                appModel.resetWorkflow()
            } label: {
                Label("New Session", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.spai(.primary, fullWidth: true))
        }
        .padding(SPAISpacing.l)
        .frame(width: 440)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(passed ? .normal : .warning, cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .onAppear { celebrate = true }
        .onChange(of: appModel.sessionComplete) { _, complete in
            celebrate = complete
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.45), tint.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 70))
                    .frame(width: 140, height: 140)
                    .scaleEffect(celebrate ? 1 : 0.6)
                    .opacity(celebrate ? 1 : 0)
                Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(passed ? AnyShapeStyle(SPAIGradient.success) : AnyShapeStyle(SPAIGradient.danger))
                    .symbolEffect(.bounce, value: celebrate)
                    .shadow(color: tint.opacity(0.6), radius: 14)
            }
            .frame(height: 120)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: celebrate)

            Text(passed ? "Session passed" : "Session failed")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(SPAIColor.textPrimary)
            Text(passed
                 ? "All five stations completed with zero contamination events."
                 : "Completed with \(appModel.contaminationCount) contamination event\(appModel.contaminationCount == 1 ? "" : "s"). Review the history below.")
                .font(.system(size: 14))
                .foregroundStyle(SPAIColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SessionReportPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
