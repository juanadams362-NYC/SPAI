//
//  StationPickerPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/17/26.
//

import SwiftUI

/// Station picker. In its compact form it rides the user's left forearm, summoned by holding
/// the forearm level and turned toward them — as if a book were lying along it.
struct StationPickerPanel: View {
    let manager: StationManager
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact: Bool = false

    /// Whether the forearm is currently held in the summoning posture. Drives a fade rather
    /// than the entity being switched off, so the panel eases out when the arm drops instead
    /// of vanishing between frames.
    var isPresented: Bool = true

    private var shouldShow: Bool {
        guard !compact || appModel.wristMenusEnabled else { return false }
        #if targetEnvironment(simulator)
        return true
        #else
        return compact ? isPresented : true
        #endif
    }

    var body: some View {
        panelContent
            .opacity(shouldShow ? 1 : 0)
            .scaleEffect(shouldShow ? 1 : 0.9)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.22), value: shouldShow)
            .allowsHitTesting(shouldShow)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : SPAISpacing.m) {
            Text(compact ? "STATIONS" : "STATIONS (SIM)")
                .font(.system(size: compact ? 8 : 12, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, compact ? 4 : 0)

            ForEach(manager.stations) { station in
                let isHere = manager.activeStation?.id == station.id
                Button {
                    manager.simulateScan(station.id)
                    appModel.announce("At \(station.name)", icon: "mappin.circle.fill")
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isHere ? SPAIColor.safe : SPAIColor.neutralMid.opacity(0.4))
                            .frame(width: compact ? 5 : 9, height: compact ? 5 : 9)
                        Text(station.name)
                            .font(.system(size: compact ? 9 : 14, weight: isHere ? .bold : .medium))
                            .foregroundStyle(.white.opacity(isHere ? 1 : 0.8))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if isHere {
                            Text("HERE")
                                .font(.system(size: compact ? 7 : 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(SPAIColor.safe)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, compact ? 6 : SPAISpacing.m)
                    .padding(.vertical, compact ? 4 : SPAISpacing.s + 2)
                    .background(
                        isHere ? SPAIColor.safe.opacity(0.14) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: SPAIRadius.small - 4)
                    )
                }
                .buttonStyle(.plain)
                // 32pt in the compact form, below the usual 44pt floor, deliberately: that
                // floor is about *angular* size, and this panel sits on the forearm at roughly
                // 30 cm rather than at a window's ~1.5 m. 32pt at 30 cm subtends a larger angle
                // than 44pt does at arm's length, so the target is easier to hit, not harder,
                // while keeping the panel small enough to live on an arm.
                .spaiHitTarget(minSize: compact ? 32 : 44, pop: compact ? 1.18 : 1.08)
                .accessibilityLabel("\(station.name) station")
                .accessibilityValue(isHere ? "Current station" : "")
                .accessibilityAddTraits(isHere ? [.isSelected] : [])
            }
        }
        .padding(compact ? 6 : SPAISpacing.l)
        .frame(width: compact ? 132 : 280)
        .spaiPanelBackground(
            opacity: appModel.panelOpacity,
            cornerRadius: compact ? SPAIRadius.medium : SPAIRadius.large
        )
        .ledBorder(cornerRadius: compact ? SPAIRadius.medium : SPAIRadius.large, lineWidth: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Station picker")
        .accessibilityHint(compact ? "Hold your left forearm level and turned toward you to show this menu" : "")
    }
}