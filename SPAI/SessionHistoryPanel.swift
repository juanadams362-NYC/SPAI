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
    @State private var isComparing = false
    @State private var compareSelectionIDs: [UUID] = []
    @State private var comparePair: ComparisonPair?

    private var isObserver: Bool { appModel.role == .observer }
    private var isSupervisor: Bool { appModel.role == .supervisor }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            if let pair = comparePair {
                backButton {
                    comparePair = nil
                    isComparing = false
                    compareSelectionIDs.removeAll()
                }
                comparisonView(pair)
            } else if let record = selected {
                backButton {
                    selected = nil
                    replayIndex = 0
                }
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
        .frame(width: comparePair != nil ? 540 : 420)
        .spaiPanel(PanelID.history)
        .animation(.easeInOut(duration: 0.2), value: selected != nil)
        .animation(.easeInOut(duration: 0.2), value: comparePair != nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session history. \(appModel.history.records.count) saved sessions.")
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.spai(.ghost, size: .small))
            .accessibilityLabel("Back to session list")
            Spacer()
        }
    }

    // MARK: - List

    private var listView: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            PanelHeader("Session History", icon: "clock.arrow.circlepath", tint: SPAIColor.accent) {
                SPAIChip(text: "\(appModel.history.records.count) saved", tint: Color.white.opacity(0.75))
            }

            if isSupervisor {
                supervisorStats
            }

            if isObserver {
                Label("Pick a session to step through what happened.", systemImage: "play.rectangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SPAIColor.accent)
            }

            if appModel.history.records.count >= 2 {
                compareToggleRow
            }

            if appModel.history.records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(SPAIColor.textTertiary)
                    Text("No sessions yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SPAIColor.textSecondary)
                    Text("Complete a workflow to save one.")
                        .font(.system(size: 13))
                        .foregroundStyle(SPAIColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SPAISpacing.l)
            } else {
                ScrollView {
                    VStack(spacing: SPAISpacing.s) {
                        ForEach(appModel.history.records) { record in
                            row(record)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 300)

                if isComparing {
                    compareSelectedButton
                }
            }
        }
    }

    private var compareToggleRow: some View {
        HStack {
            Button {
                isComparing.toggle()
                compareSelectionIDs.removeAll()
            } label: {
                Label(isComparing ? "Cancel Compare" : "Compare Sessions",
                      systemImage: isComparing ? "xmark" : "square.split.2x1")
            }
            .buttonStyle(.spai(isComparing ? .tinted(SPAIColor.warning) : .tinted(SPAIColor.accent), size: .small))
            .accessibilityLabel(isComparing ? "Cancel comparing sessions" : "Compare two sessions")
            Spacer()
            if isComparing {
                Text("\(compareSelectionIDs.count)/2 selected")
                    .font(SPAIFont.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SPAIColor.textTertiary)
            }
        }
    }

    private var compareSelectedButton: some View {
        let ready = compareSelectionIDs.count == 2
        return Button {
            guard ready else { return }
            let records = compareSelectionIDs.compactMap { id in
                appModel.history.records.first { $0.id == id }
            }
            guard records.count == 2 else { return }
            comparePair = ComparisonPair(a: records[0], b: records[1])
        } label: {
            Label("Compare Selected", systemImage: "square.split.2x1.fill")
        }
        .buttonStyle(.spai(.primary, fullWidth: true))
        .disabled(!ready)
        .accessibilityLabel(ready ? "Compare selected sessions" : "Select two sessions to compare")
    }

    private func toggleCompareSelection(_ record: SessionRecord) {
        if let index = compareSelectionIDs.firstIndex(of: record.id) {
            compareSelectionIDs.remove(at: index)
        } else {
            if compareSelectionIDs.count == 2 {
                compareSelectionIDs.removeFirst()
            }
            compareSelectionIDs.append(record.id)
        }
    }

    private var supervisorStats: some View {
        let rate = Int(appModel.history.passRate * 100)
        let passed = appModel.history.records.filter { $0.passed }.count
        let total = appModel.history.records.count
        let rateColor = rate >= 80 ? SPAIColor.safe : SPAIColor.warning

        return HStack(spacing: SPAISpacing.l) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : CGFloat(appModel.history.passRate))
                    .stroke(rateColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: rateColor.opacity(0.5), radius: 4)
                Text(total == 0 ? "—" : "\(rate)%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(total == 0 ? SPAIColor.textTertiary : rateColor)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text("Pass rate")
                    .spaiEyebrow()
                Text("\(passed) of \(total) passed")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text(rate >= 80 ? "On target" : "Below the 80% target")
                    .font(SPAIFont.caption.weight(.medium))
                    .foregroundStyle(total == 0 ? SPAIColor.textTertiary : rateColor)
            }
            Spacer()
        }
        .padding(SPAISpacing.m)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pass rate \(total == 0 ? "not available" : "\(rate) percent"). \(passed) of \(total) sessions passed.")
    }

    // MARK: - Replay (observer)

    private func replayView(_ record: SessionRecord) -> some View {
        let events = record.events.reversed().map { $0 }   // oldest first for replay
        let safeIndex = min(replayIndex, max(events.count - 1, 0))

        return VStack(alignment: .leading, spacing: SPAISpacing.m) {
            PanelHeader("Replay", icon: "play.rectangle.fill", tint: SPAIColor.accent) {
                Text(events.isEmpty ? "—" : "\(safeIndex + 1) of \(events.count)")
                    .font(SPAIFont.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SPAIColor.accent)
            }

            Text(record.dateText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SPAIColor.textTertiary)

            if events.isEmpty {
                Text("No events recorded in this session.")
                    .font(.system(size: 14))
                    .foregroundStyle(SPAIColor.textSecondary)
            } else {
                ConfidenceBar(value: Double(safeIndex + 1) / Double(events.count), color: SPAIColor.accent)

                Text(events[safeIndex])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SPAIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(SPAISpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(eventTint(events[safeIndex]).opacity(0.16),
                                in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                            .strokeBorder(eventTint(events[safeIndex]).opacity(0.4), lineWidth: 1)
                    }
                    .accessibilityLabel("Event \(safeIndex + 1) of \(events.count). \(events[safeIndex])")

                HStack(spacing: SPAISpacing.s) {
                    Button {
                        replayIndex = max(0, safeIndex - 1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .buttonStyle(.spai(.glass))
                    .disabled(safeIndex == 0)
                    .accessibilityLabel("Previous event")

                    Button {
                        replayIndex = min(events.count - 1, safeIndex + 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .buttonStyle(.spai(.primary))
                    .disabled(safeIndex >= events.count - 1)
                    .accessibilityLabel("Next event")

                    Spacer()

                    resultChip(record.passed)
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

    private func resultChip(_ passed: Bool) -> some View {
        SPAIChip(text: passed ? "Passed" : "Failed",
                 icon: passed ? "checkmark.seal.fill" : "xmark.seal.fill",
                 tint: passed ? SPAIColor.safe : SPAIColor.critical)
    }

    // MARK: - Row

    private func row(_ record: SessionRecord) -> some View {
        let isSelected = compareSelectionIDs.contains(record.id)
        let tint = record.passed ? SPAIColor.safe : SPAIColor.critical
        return Button {
            if isComparing {
                toggleCompareSelection(record)
            } else {
                selected = record
                replayIndex = 0
            }
        } label: {
            HStack(spacing: SPAISpacing.m) {
                if isComparing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? SPAIColor.accent : Color.white.opacity(0.4))
                }
                Image(systemName: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.dateText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SPAIColor.textPrimary)
                    Text("\(record.passed ? "Passed" : "Failed") · \(record.contaminationCount) events · \(record.durationText) · \(record.role)")
                        .font(SPAIFont.caption)
                        .foregroundStyle(SPAIColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if !isComparing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SPAIColor.textTertiary)
                }
            }
            .padding(12)
            .background(isSelected ? SPAIColor.accent.opacity(0.16) : SPAIColor.surface,
                        in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                    .strokeBorder(isSelected ? SPAIColor.accent.opacity(0.5) : SPAIColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .spaiHitTarget()
        .accessibilityLabel("\(record.dateText). \(record.passed ? "Passed" : "Failed"). \(record.contaminationCount) contamination events. Duration \(record.durationText). Run as \(record.role). \(isComparing ? (isSelected ? "Selected for comparison." : "Tap to select for comparison.") : (isObserver ? "Opens replay." : "Opens report."))")
    }

    // MARK: - Comparison

    private func comparisonView(_ pair: ComparisonPair) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            PanelHeader("Session Comparison", icon: "square.split.2x1.fill", tint: SPAIColor.accent)

            HStack(alignment: .top, spacing: SPAISpacing.m) {
                comparisonColumn(pair.a)
                comparisonColumn(pair.b)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparing session from \(pair.a.dateText) against session from \(pair.b.dateText).")
    }

    private func comparisonColumn(_ record: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text(record.dateText)
                .font(SPAIFont.caption.weight(.semibold))
                .foregroundStyle(SPAIColor.textTertiary)

            resultChip(record.passed)

            comparisonStat("Contamination", "\(record.contaminationCount)")
            comparisonStat("Duration", record.durationText)
            comparisonStat("Role", record.role)
        }
        .padding(SPAISpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.dateText). \(record.passed ? "Passed" : "Failed"). \(record.contaminationCount) contamination events. Duration \(record.durationText). Run as \(record.role).")
    }

    private func comparisonStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SPAIFont.caption.weight(.semibold))
                .foregroundStyle(SPAIColor.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SPAIColor.textPrimary)
        }
    }
}

private struct ComparisonPair: Equatable {
    let a: SessionRecord
    let b: SessionRecord

    static func == (lhs: ComparisonPair, rhs: ComparisonPair) -> Bool {
        lhs.a.id == rhs.a.id && lhs.b.id == rhs.b.id
    }
}

struct SavedReportView: View {
    let record: SessionRecord

    private var tint: Color { record.passed ? SPAIColor.safe : SPAIColor.critical }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            HStack(spacing: SPAISpacing.m) {
                Image(systemName: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 58, height: 58)
                    .background(tint.opacity(0.14), in: Circle())
                    .shadow(color: tint.opacity(0.4), radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.passed ? "Session passed" : "Session failed")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(SPAIColor.textPrimary)
                    Text(record.dateText)
                        .font(.system(size: 13))
                        .foregroundStyle(SPAIColor.textSecondary)
                    Text("Run as \(record.role)")
                        .font(SPAIFont.caption)
                        .foregroundStyle(SPAIColor.textTertiary)
                }
            }

            HStack(spacing: 10) {
                MetricTile(label: "Alerts", value: "\(record.contaminationCount)",
                           icon: "exclamationmark.triangle.fill", tint: tint)
                MetricTile(label: "Duration", value: record.durationText,
                           icon: "clock.fill", tint: SPAIColor.accent)
            }

            Text("Event history")
                .spaiEyebrow()

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(record.events, id: \.self) { event in
                        Text(event)
                            .font(SPAIFont.mono)
                            .foregroundStyle(SPAIColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 200)
            .padding(12)
            .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved report. Session \(record.passed ? "passed" : "failed"). \(record.contaminationCount) contamination events. Duration \(record.durationText). Run as \(record.role).")
    }
}

#Preview {
    SessionHistoryPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
