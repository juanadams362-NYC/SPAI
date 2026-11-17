//
//  StationPickerPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/17/26.
//

import SwiftUI

/// The list of stations. `compact` is the left-wrist version: turn the back
/// of your left wrist toward you, like checking a watch, and it rises above
/// it.
struct StationPickerPanel: View {
    let manager: StationManager
    @Environment(AppModel.self) private var appModel
    var compact: Bool = false

    /// Fixed size of the wrist version in points, so the hand tracker knows
    /// how much room to leave between the menu and the arm.
    static let compactSize = CGSize(width: 216, height: 300)

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : SPAISpacing.m) {
            Label(compact ? "Stations" : "Stations (sim)", systemImage: "mappin.and.ellipse")
                .spaiEyebrow()
                .padding(.leading, 4)

            ForEach(Array(manager.stations.enumerated()), id: \.element.id) { index, station in
                stationRow(station, number: index + 1)
            }
        }
        .padding(compact ? SPAISpacing.s + 4 : SPAISpacing.l)
        .frame(width: compact ? Self.compactSize.width : 280,
               height: compact ? Self.compactSize.height : nil,
               alignment: .top)
        .modifier(StationPickerChrome(compact: compact))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stations")
    }

    private func stationRow(_ station: Station, number: Int) -> some View {
        let isHere = manager.activeStation?.id == station.id
        return Button {
            manager.simulateScan(station.id)
        } label: {
            HStack(spacing: SPAISpacing.s) {
                // The number is the quickest thing to find at a glance, and
                // matches the order on the workflow panel.
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isHere ? SPAIColor.onFill : SPAIColor.primaryBright)
                    .frame(width: 28, height: 28)
                    .background(isHere ? AnyShapeStyle(SPAIGradient.success) : AnyShapeStyle(SPAIColor.primary.opacity(0.14)),
                                in: Circle())

                Text(station.name)
                    .font(.system(size: compact ? 15 : 16, weight: isHere ? .semibold : .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isHere {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SPAIColor.safe)
                }
            }
            .padding(.horizontal, SPAISpacing.s + 2)
            .frame(height: 46)
            .background(isHere ? SPAIColor.safe.opacity(0.16) : SPAIColor.surface,
                        in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                    .strokeBorder(isHere ? SPAIColor.safe.opacity(0.7) : SPAIColor.hairline, lineWidth: isHere ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: SPAIRadius.small))
        .hoverEffect(.highlight)
        .accessibilityLabel("Station \(number), \(station.name)")
        .accessibilityAddTraits(isHere ? .isSelected : [])
        .accessibilityHint(isHere ? "You are here" : "Move to this station")
    }
}

/// Wrist version gets the opaque wrist background; the room version gets the
/// same chrome as every other room panel.
private struct StationPickerChrome: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content.spaiWristBackground()
        } else {
            content.spaiPanel()
        }
    }
}
