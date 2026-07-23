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
    @State private var replayIndex: Int = 0

    private var isObserver: Bool { appModel.role == .observer }
    private var isSupervisor: Bool { appModel.role == .supervisor }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            if let record = selected {
                detailHeader
                if isObserver {
                    replayView(record)
                } else {
                    SavedReportView(record: record)
                }
            } else {
                listView
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 400)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.easeInOut(duration: 0.2), value: selected != nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session history. \(appModel.history.records.count) saved sessions.")
    }

    private var detailHeader: some View {
        HStack {
            Button {
                selected = nil
                replayIndex = 0
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to session list")
            Spacer()
        }
    }

    private var listView: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            HStack {
                Text("SESSION HISTORY")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(appModel.history.records.count) saved")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if isSupervisor {
                supervisorStats
            }

            if isObserver {
                Text("Pick a session to step through what happened.")
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.accent)
            }

            if appModel.history.records.isEmpty {
                Text("No sessions yet. Complete a workflow to save one.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, SPAISpacing.l)
            } else {
                ScrollView {
                    VStack(spacing: SPAISpacing.s) {
                        ForEach(appModel.history.records) { record in
                            row(record)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private var supervisorStats: some View {
        let rate = Int(appModel.history.passRate * 100)
        let passed = appModel.history.records.filter { $0.passed }.count
        let total = appModel.history.records.count

        return HStack(spacing: SPAISpacing.xl) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PASS RATE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text(total == 0 ? "—" : "\(rate)%")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(rate >= 80 ? SPAIColor.safe : SPAIColor.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(passed) of \(total) passed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(SPAISpacing.m)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pass rate \(total == 0 ? "not available" : "\(rate) percent"). \(passed) of \(total) sessions passed.")
    }

    private func replayView(_ record: SessionRecord) -> some View {
        let events = record.events.reversed().map { $0 }   // oldest first for replay
        let safeIndex = min(replayIndex, max(events.count - 1, 0))

        return VStack(alignment: .leading, spacing: SPAISpacing.m) {
            HStack {
                Text("REPLAY · \(record.dateText)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(events.isEmpty ? "—" : "\(safeIndex + 1) of \(events.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SPAIColor.accent)
            }

            if events.isEmpty {
                Text("No events recorded in this session.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text(events[safeIndex])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(SPAISpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(eventTint(events[safeIndex]).opacity(0.18),
                                in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                    .accessibilityLabel("Event \(safeIndex + 1) of \(events.count). \(events[safeIndex])")

                HStack(spacing: SPAISpacing.m) {
                    Button {
                        replayIndex = max(0, safeIndex - 1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, SPAISpacing.m)
                            .padding(.vertical, SPAISpacing.s)
                            .background(SPAIColor.neutralMid.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                    }
                    .buttonStyle(.plain)
                    .disabled(safeIndex == 0)
                    .accessibilityLabel("Previous event")

                    Button {
                        replayIndex = min(events.count - 1, safeIndex + 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, SPAISpacing.m)
                            .padding(.vertical, SPAISpacing.s)
                            .background(SPAIColor.primary,
                                        in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                    }
                    .buttonStyle(.plain)
                    .disabled(safeIndex >= events.count - 1)
                    .accessibilityLabel("Next event")

                    Spacer()

                    Label(record.passed ? "Passed" : "Failed",
                          systemImage: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(record.passed ? SPAIColor.safe : SPAIColor.critical)
                }
            }
        }
    }

    private func eventTint(_ event: String) -> Color {
        let lower = event.lowercased()
        if lower.contains("contamination") { return SPAIColor.critical }
        if lower.contains("failed") || lower.contains("rejected") { return SPAIColor.warning }
        if lower.contains("completed") { return SPAIColor.safe }
        return SPAIColor.neutralMid
    }

    private func row(_ record: SessionRecord) -> some View {
        Button {
            selected = record
            replayIndex = 0
        } label: {
            HStack(spacing: SPAISpacing.m) {
                Image(systemName: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(record.passed ? SPAIColor.safe : SPAIColor.critical)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.dateText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(record.passed ? "Passed" : "Failed") · \(record.contaminationCount) events · \(record.durationText) · \(record.role)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(SPAISpacing.m)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.dateText). \(record.passed ? "Passed" : "Failed"). \(record.contaminationCount) contamination events. Duration \(record.durationText). Run as \(record.role). \(isObserver ? "Opens replay." : "Opens report.")")
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
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(record.passed ? SPAIColor.safe : SPAIColor.critical)
                    Text(record.dateText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("Run as \(record.role)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            HStack(spacing: SPAISpacing.xl) {
                stat("Contamination", "\(record.contaminationCount)")
                stat("Duration", record.durationText)
            }

            Divider().overlay(.white.opacity(0.3))

            Text("EVENT HISTORY")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(record.events, id: \.self) { event in
                        Text(event)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved report. Session \(record.passed ? "passed" : "failed"). \(record.contaminationCount) contamination events. Duration \(record.durationText). Run as \(record.role).")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    SessionHistoryPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
