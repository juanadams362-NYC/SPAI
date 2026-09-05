//
//  StationPickerPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/17/26.
//

import SwiftUI

struct StationPickerPanel: View {
    let manager: StationManager
    @Environment(AppModel.self) private var appModel
    var compact: Bool = false

    /// Whether the wrist this panel rides on is currently tracked. Drives a fade rather than
    /// the entity being switched off, so the panel eases out when the arm drops instead of
    /// vanishing between frames.
    var isHandVisible: Bool = true

    private var shouldShow: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return isHandVisible
        #endif
    }

    var body: some View {
        panelContent
            .opacity(shouldShow ? 1 : 0)
            .scaleEffect(shouldShow ? 1 : 0.9)
            .animation(.easeInOut(duration: 0.22), value: shouldShow)
            .allowsHitTesting(shouldShow)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: compact ? SPAISpacing.s : SPAISpacing.m) {
            Text(compact ? "STATIONS" : "STATIONS (SIM)")
                .font(.system(size: compact ? 9 : 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            ForEach(manager.stations) { station in
                Button {
                    manager.simulateScan(station.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(manager.activeStation?.id == station.id ? SPAIColor.safe : SPAIColor.neutralMid.opacity(0.4))
                            .frame(width: compact ? 6 : 9, height: compact ? 6 : 9)
                        Text(station.name)
                            .font(.system(size: compact ? 11 : 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        if manager.activeStation?.id == station.id {
                            Text("HERE")
                                .font(.system(size: compact ? 8 : 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(SPAIColor.safe)
                        }
                    }
                    .padding(.horizontal, compact ? SPAISpacing.s : SPAISpacing.m)
                    .padding(.vertical, compact ? SPAISpacing.s : SPAISpacing.s + 2)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
                .spaiHitTarget()
            }
        }
        .padding(compact ? SPAISpacing.m : SPAISpacing.l)
        .frame(width: compact ? 170 : 280)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }
}