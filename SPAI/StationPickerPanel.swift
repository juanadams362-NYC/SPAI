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

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : SPAISpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: compact ? 9 : 12, weight: .bold))
                    .foregroundStyle(SPAIColor.primary)
                Text(compact ? "Stations" : "Stations (sim)")
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(SPAIColor.textTertiary)
            }
            .padding(.bottom, 2)

            ForEach(manager.stations) { station in
                stationRow(station)
            }
        }
        .padding(compact ? 12 : SPAISpacing.l)
        .frame(width: compact ? 190 : 290)
        .spaiPanelBackground(opacity: appModel.panelOpacity, cornerRadius: compact ? 22 : SPAIRadius.large)
        .ledBorder(cornerRadius: compact ? 22 : SPAIRadius.large, lineWidth: 1.5)
    }

    private func stationRow(_ station: Station) -> some View {
        let isActive = manager.activeStation?.id == station.id

        return Button {
            manager.simulateScan(station.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: station.step.icon)
                    .font(.system(size: compact ? 10 : 13, weight: .semibold))
                    .foregroundStyle(isActive ? SPAIColor.onFill : SPAIColor.primaryBright)
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                    .background(
                        isActive ? AnyShapeStyle(SPAIGradient.success) : AnyShapeStyle(SPAIColor.primary.opacity(0.14)),
                        in: Circle()
                    )
                Text(station.name)
                    .font(.system(size: compact ? 12 : 14, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? SPAIColor.textPrimary : SPAIColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if isActive {
                    Text("HERE")
                        .font(.system(size: compact ? 8 : 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(SPAIColor.safe)
                }
            }
            .padding(.horizontal, compact ? 8 : SPAISpacing.m)
            .padding(.vertical, compact ? 4 : 8)
            .background(
                isActive ? SPAIColor.safe.opacity(0.14) : SPAIColor.surface,
                in: RoundedRectangle(cornerRadius: compact ? 10 : SPAIRadius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 10 : SPAIRadius.small, style: .continuous)
                    .strokeBorder(isActive ? SPAIColor.safe.opacity(0.4) : SPAIColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .spaiHitTarget(cornerRadius: compact ? 10 : SPAIRadius.small)
        .accessibilityLabel("\(station.name)\(isActive ? ", current station" : "")")
    }
}
