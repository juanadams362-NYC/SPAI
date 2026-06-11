//
//  DetectionPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/11/26.
//


//
//  DetectionPanel.swift
//  SPAI
//
//  Merged awareness panel. Surfaces ONLY contamination risk to the user
//  (glove/hand run silently as a PPE check), plus AAMI ST79 environment
//  readouts. Replaces the floating glove/hand/contamination markers and
//  the separate environmental status panel.
//
//  Values are mock for now; wired to the backend /detect + sensors later.
//

import SwiftUI

struct DetectionPanel: View {
    // --- Mock state (replace with backend feed) ---
    private let contaminationRisk: Double = 0.76      // 0...1
    private let ppePassing = true
    private let temperatureF = 70
    private let humidityPct = 44
    private let positivePressure = true

    private var riskHigh: Bool { contaminationRisk >= 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header
            contaminationRow
            divider
            environmentSection
            divider
            ppeRow
        }
        .padding(SPAISpacing.l)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
    }

    // Eyebrow label; shows an amber RISK tag only when contamination is high.
    private var header: some View {
        HStack {
            Text("DETECTION")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            if riskHigh {
                HStack(spacing: 6) {
                    Circle().fill(SPAIColor.warning).frame(width: 7, height: 7)
                    Text("RISK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPAIColor.warning)
                }
            }
        }
    }

    // The ONLY detection the user sees, with its percentage.
    private var contaminationRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(riskHigh ? SPAIColor.warning : SPAIColor.safe)
                .frame(width: 10, height: 10)
                .shadow(color: (riskHigh ? SPAIColor.warning : SPAIColor.safe).opacity(0.8), radius: 4)
            Text("Contamination risk")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("\(Int(contaminationRisk * 100))%")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(riskHigh ? SPAIColor.warning : SPAIColor.safe)
        }
    }

    // ST79 environment readouts; each turns amber if out of range.
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text("ENVIRONMENT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.4))
            environmentRow(icon: "thermometer.medium", label: "Temperature",
                           value: "\(temperatureF)°F", ok: (68...73).contains(temperatureF))
            environmentRow(icon: "humidity.fill", label: "Humidity",
                           value: "\(humidityPct)%", ok: (30...60).contains(humidityPct))
            environmentRow(icon: "wind", label: "Air pressure",
                           value: positivePressure ? "Positive" : "Negative", ok: positivePressure)
        }
    }

    private func environmentRow(icon: String, label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(ok ? SPAIColor.safe : SPAIColor.warning).frame(width: 8, height: 8)
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    // Glove + hand collapsed into a single pass/fail line — no percentages.
    private var ppeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: ppePassing ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(ppePassing ? SPAIColor.safe : SPAIColor.warning)
            Text(ppePassing ? "PPE check passing" : "PPE check failed")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text("glove · hand")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
    }
}

#Preview {
    DetectionPanel()
        .padding(60)
        .background(.black)
}
