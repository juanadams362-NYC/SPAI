//
//  StationPickerPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/17/26.
//

import SwiftUI

struct StationPickerPanel: View {
    let manager: StationManager

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("STATIONS (SIM)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            ForEach(manager.stations) { station in
                Button {
                    manager.simulateScan(station.id)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(manager.activeStation?.id == station.id ? SPAIColor.safe : SPAIColor.neutralMid.opacity(0.4))
                            .frame(width: 9, height: 9)
                        Text(station.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        if manager.activeStation?.id == station.id {
                            Text("HERE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(SPAIColor.safe)
                        }
                    }
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }
}