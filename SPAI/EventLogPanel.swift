//
//  EventLogPanel.swift
//  SPAI
//

import SwiftUI

struct EventLogPanel: View {
    @Environment(AppModel.self) private var appModel

    private var events: [LogEvent] { appModel.eventLog }

    private var warningCount: Int {
        events.filter { $0.kind == .warning }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            PanelHeader("Event Log", icon: "waveform.path.ecg", tint: SPAIColor.accent) {
                HStack(spacing: 6) {
                    if warningCount > 0 {
                        SPAIChip(text: "\(warningCount)", icon: "exclamationmark.triangle.fill", tint: SPAIColor.warning)
                    }
                    SPAIChip(text: "\(events.count) events", tint: Color.white.opacity(0.75))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { event in
                        eventRow(event,
                                 isNewest: event.id == events.first?.id,
                                 isLast: event.id == events.last?.id)
                            .transition(AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity))
                    }
                }
                .padding(.top, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 236)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: Color.black, location: 0),
                        .init(color: Color.black, location: 0.82),
                        .init(color: Color.black.opacity(0), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 360)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.snappy(duration: 0.35), value: events.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event log. \(events.count) events. Most recent: \(events.first?.message ?? "none").")
    }

    private func eventRow(_ event: LogEvent, isNewest: Bool, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.message)
                .font(.system(size: 15, weight: isNewest ? .semibold : .regular))
                .foregroundStyle(isNewest ? SPAIColor.textPrimary : Color.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            Text(event.timestamp)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(SPAIColor.textTertiary)
        }
        .padding(.leading, 26)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            // Timeline rail + node.
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(isLast ? 0 : 0.12))
                    .frame(width: 2)
                    .padding(.top, 16)
                Circle()
                    .fill(event.kind.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: event.kind.color.opacity(0.8), radius: isNewest ? 6 : 2)
                    .padding(.top, 5)
            }
            .frame(width: 12)
            .padding(.leading, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.message), at \(event.timestamp)")
    }
}

#Preview {
    EventLogPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
