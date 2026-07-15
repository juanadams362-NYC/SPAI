//
//  EventLogPanel.swift
//  SPAI
//

import SwiftUI

struct EventLogPanel: View {
    @Environment(AppModel.self) private var appModel

    private var events: [LogEvent] { appModel.eventLog }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SPAISpacing.s) {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(SPAISpacing.l)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    private var header: some View {
        HStack {
            Text("EVENT LOG")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text("\(events.count) events")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func eventRow(_ event: LogEvent) -> some View {
        HStack(alignment: .top, spacing: SPAISpacing.s + 2) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 13))
                .foregroundStyle(event.kind.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.timestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

#Preview {
    EventLogPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
