//
//  LogEvent.swift
//  SPAI
//
//  Created by Juan Adams on 6/7/26.
//


//
//  EventLogPanel.swift
//  SPAI
//
//  A live scrolling activity feed of workflow + compliance events.
//  Newest event on top. Later this is fed by the FSM / backend; for now
//  it carries sample entries and a demo "add event" action.
//

import SwiftUI

/// One logged event in the activity feed.
struct LogEvent: Identifiable {
    let id = UUID()
    let timestamp: String
    let message: String
    let kind: Kind

    enum Kind {
        case info, success, warning

        var color: Color {
            switch self {
            case .info:    return SPAIColor.accent
            case .success: return SPAIColor.safe
            case .warning: return SPAIColor.warning
            }
        }

        var icon: String {
            switch self {
            case .info:    return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }
}

struct EventLogPanel: View {
    // Seeded with a few sample events; newest first.
    @State private var events: [LogEvent] = [
        LogEvent(timestamp: "22:47:39", message: "Session started", kind: .info),
        LogEvent(timestamp: "22:47:41", message: "Decontamination step ready", kind: .info),
        LogEvent(timestamp: "22:47:52", message: "Gloves detected — PPE check passing", kind: .success)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header

            // Scrollable feed. Capped height so it doesn't grow forever.
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

    // MARK: - Header

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

    // MARK: - Event row

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

    /// Public helper so other parts of the app can push events here later.
    func addEvent(_ message: String, kind: LogEvent.Kind) {
        let time = Date().formatted(date: .omitted, time: .standard)
        events.insert(LogEvent(timestamp: time, message: message, kind: kind), at: 0)
    }
}

#Preview {
    EventLogPanel()
        .padding(60)
        .background(.black)
}