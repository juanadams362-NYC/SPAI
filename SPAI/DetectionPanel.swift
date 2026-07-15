//
//  DetectionPanel.swift
//  SPAI
//

import SwiftUI

struct DetectionPanel: View {
    @Environment(AppModel.self) private var appModel
    let service: DetectionService

    private let temperatureF = 70
    private let humidityPct = 44
    private let positivePressure = true

    private var contaminationRisk: Double { service.contaminationRisk }
    private var ppePassing: Bool { service.ppePassing }
    private var riskHigh: Bool { contaminationRisk >= 0.5 }

    private var borderState: BorderState {
        if !service.hasResult { return .normal }
        if contaminationRisk >= 0.5 { return .critical }
        if contaminationRisk > 0.10 { return .warning }
        return .normal
    }

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
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(borderState, cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.easeInOut(duration: 0.4), value: riskHigh)
        .onChange(of: service.contaminationRisk) { old, new in
            if old < 0.5 && new >= 0.5 {
                SoundManager.shared.playContaminationAlert()
                if !appModel.isHalted {
                    appModel.raiseContamination()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("DETECTION")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if service.isLoading {
                Text("…")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            } else if riskHigh {
                HStack(spacing: 6) {
                    Circle().fill(SPAIColor.warning).frame(width: 7, height: 7)
                    Text("RISK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPAIColor.warning)
                }
            }
        }
    }

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
            if service.hasResult {
                Text("\(Int(contaminationRisk * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(riskHigh ? SPAIColor.warning : SPAIColor.safe)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text("ENVIRONMENT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var ppeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: ppePassing ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(ppePassing ? SPAIColor.safe : SPAIColor.warning)
            Text(service.hasResult ? (ppePassing ? "PPE check passing" : "PPE check failed") : "PPE check idle")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Text("glove · hand")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
    }
}

#Preview {
    DetectionPanel(service: DetectionService())
        .environment(AppModel())
        .padding(60)
        .background(.black)
}

