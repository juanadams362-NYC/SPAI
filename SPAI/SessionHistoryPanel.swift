//
//  SessionHistoryPanel.swift
//  SPAI
//
//  Created by AVP Student on 7/15/26.
//

import SwiftUI

struct SessionHistoryPanel: View {
    @Environment(AppModel.self) private var appModel
    @State private var selected: SessionRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            HStack {
                Text("SESSION HISTORY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(appModel.history.records.count) saved")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if appModel.history.records.isEmpty {
                Text("No sessions yet. Complete a workflow to save one.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, SPAISpacing.l)
            } else {
                ScrollView {
                    VStack(spacing: SPAISpacing.s) {
                        ForEach(appModel.history.records) { record in
                            row(record)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 380)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .sheet(item: $selected) { record in
            SavedReportView(record: record)
        }
    }

    private func row(_ record: SessionRecord) -> some View {
        Button {
            selected = record
        } label: {
            HStack(spacing: SPAISpacing.m) {
                Image(systemName: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(record.passed ? SPAIColor.safe : SPAIColor.critical)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.dateText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(record.passed ? "Passed" : "Failed") · \(record.contaminationCount) events · \(record.durationText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(SPAISpacing.m)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }
        .buttonStyle(.plain)
    }
}

struct SavedReportView: View {
    let record: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            HStack(spacing: SPAISpacing.m) {
                Image(systemName: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(record.passed ? SPAIColor.safe : SPAIColor.critical)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.passed ? "SESSION PASSED" : "SESSION FAILED")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(record.passed ? SPAIColor.safe : SPAIColor.critical)
                    Text(record.dateText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(spacing: SPAISpacing.xl) {
                stat("Contamination", "\(record.contaminationCount)")
                stat("Duration", record.durationText)
            }

            Divider().overlay(.white.opacity(0.2))

            Text("EVENT HISTORY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(record.events, id: \.self) { event in
                        Text(event)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(SPAISpacing.xl)
        .frame(minWidth: 420, minHeight: 480)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}
