//
//  EnvironmentReading.swift
//  SPAI
//
//  Created by Juan Adams on 6/7/26.
//


//
//  CompliancePanel.swift
//  SPAI
//
//  Environmental + compliance status panel from the Figma. Shows an
//  overall compliance state and a few live environmental readouts.
//  The overall state is driven by the readings so it stays honest.
//

import SwiftUI

/// A single environmental reading (temperature, humidity, etc.).
struct EnvironmentReading: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
    let inRange: Bool   // drives whether this reading counts as compliant
}

struct CompliancePanel: View {
    // Sample readings for now. Later these come from sensors / backend.
    private let readings: [EnvironmentReading] = [
        EnvironmentReading(label: "Temperature", value: "68°F", icon: "thermometer.medium", inRange: true),
        EnvironmentReading(label: "Humidity",    value: "44%",  icon: "humidity",           inRange: true),
        EnvironmentReading(label: "Air Pressure", value: "Positive", icon: "wind",          inRange: true)
    ]

    // Overall compliance = every reading in range. Derived, not hardcoded,
    // so the headline can't lie about the readings below it.
    private var allCompliant: Bool {
        readings.allSatisfy { $0.inRange }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("ENVIRONMENTAL STATUS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))

            complianceHeadline

            VStack(spacing: SPAISpacing.s) {
                ForEach(readings) { reading in
                    readingRow(reading)
                }
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    // MARK: - Headline

    private var complianceHeadline: some View {
        HStack(spacing: SPAISpacing.s + 4) {
            Image(systemName: allCompliant ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(allCompliant ? SPAIColor.safe : SPAIColor.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(allCompliant ? "All Systems Compliant" : "Attention Needed")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(allCompliant ? "Environment within standards" : "One or more readings out of range")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(SPAISpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (allCompliant ? SPAIColor.safe : SPAIColor.warning).opacity(0.12),
            in: RoundedRectangle(cornerRadius: SPAIRadius.medium)
        )
    }

    // MARK: - Reading row

    private func readingRow(_ reading: EnvironmentReading) -> some View {
        HStack(spacing: SPAISpacing.s + 4) {
            Image(systemName: reading.icon)
                .font(.system(size: 15))
                .foregroundStyle(reading.inRange ? SPAIColor.accent : SPAIColor.warning)
                .frame(width: 24)

            Text(reading.label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text(reading.value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CompliancePanel()
        .padding(60)
        .background(.black)
}