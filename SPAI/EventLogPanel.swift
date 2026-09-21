//
//  EventLogPanel.swift
//  SPAI
//

// All sizing is now proportional to panelWidth. Change panelWidth to update look everywhere.

import SwiftUI

struct EventLogPanel: View {
    @Environment(AppModel.self) private var appModel

    var panelWidth: CGFloat = 350 // Default for previews and fallback

    private var events: [LogEvent] { appModel.eventLog }

    var body: some View {
        VStack(alignment: .leading, spacing: panelWidth * 0.015) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: panelWidth * 0.01) {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
            .frame(maxHeight: panelWidth * 0.63)

            PanelDragHandle(panelID: "eventLog")
                .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
        }
        .padding(panelWidth * 0.07)
        .frame(width: panelWidth)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event log. \(events.count) events. Most recent: \(events.first?.message ?? "none").")
    }

    private var header: some View {
        HStack {
            Text("EVENT LOG")
                .font(.system(size: panelWidth * 0.045, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("\(events.count) events")
                .font(.system(size: panelWidth * 0.034, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func eventRow(_ event: LogEvent) -> some View {
        HStack(alignment: .top, spacing: panelWidth * 0.012 + 2) {
            Image(systemName: event.kind.icon)
                .font(.system(size: panelWidth * 0.04))
                .foregroundStyle(event.kind.color)
                .frame(width: panelWidth * 0.05)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(size: panelWidth * 0.04))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.timestamp)
                    .font(.system(size: panelWidth * 0.034, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.message), at \(event.timestamp)")
    }
}

#Preview {
    EventLogPanel(panelWidth: 350)
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
