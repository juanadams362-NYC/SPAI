//
//  DetectionPanel.swift
//  SPAI
//

// All sizing is now proportional to panelWidth. Change panelWidth to update look everywhere.

import SwiftUI

struct DetectionPanel: View {
    @Environment(AppModel.self) private var appModel
    let service: DetectionService
    var panelWidth: CGFloat = 350 // Default for previews and fallback
    private let environment = EnvironmentService.shared

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

    private var ppeText: String {
        service.hasResult ? (ppePassing ? "PPE check passing" : "PPE check failed") : "PPE check idle"
    }

    /// Says so when detection has quietly degraded.
    ///
    /// The app falls back from the backend to the on-device model whenever the backend is
    /// unreachable — a different model at a different threshold. The status bar showed
    /// "ON-DEVICE" but nothing said *why*, so a machine with a typo in its Backend URL just
    /// behaved differently from the one next to it with no way to tell. This is the panel the
    /// user is already reading when they wonder why detection looks off.
    private func degradedBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: panelWidth * 0.017) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: panelWidth * 0.031, weight: .semibold))
                .foregroundStyle(SPAIColor.warning)
            Text(note)
                .font(.system(size: panelWidth * 0.031))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, panelWidth * 0.02)
        .padding(.vertical, panelWidth * 0.017)
        .background(SPAIColor.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: SPAIRadius.small - 4))
        .overlay(
            RoundedRectangle(cornerRadius: SPAIRadius.small - 4)
                .stroke(SPAIColor.warning.opacity(0.4), lineWidth: 1)
        )
        .accessibilityLabel("Detection degraded. \(note)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: panelWidth * 0.02) {
            header
            if let note = service.lastPathNote { degradedBanner(note) }
            contaminationRow
            divider
            environmentSection
            divider
            ppeRow
            PanelDragHandle(panelID: "detection")
        }
        .padding(panelWidth * 0.07)
        .frame(width: panelWidth, alignment: .leading)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(borderState, cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.easeInOut(duration: 0.4), value: riskHigh)
        .accessibilityElement(children: .contain)
        // Risk is conveyed visually by the border colour alone, which is invisible to
        // VoiceOver and to anyone who cannot distinguish the colours — so it is stated here.
        .accessibilityLabel(
            service.hasResult
                ? "Detection. \(ppeText). Contamination risk \(Int(contaminationRisk * 100)) percent."
                : "Detection. Nothing detected yet — show SPAI an image, video, or live camera."
        )
        .onChange(of: service.contaminationRisk) { old, new in

            if old < 0.5 && new >= 0.5 && appModel.shouldHaltOnBareHand {
                SoundManager.shared.playContaminationAlert()
                // force: a safety alert speaks whether or not the user
                // turned spoken guidance on. Anchored to the same panel as the
                // alert tone so the whole warning comes from one direction.
                SpeechManager.shared.speak(
                    "Contamination detected. Bare hand visible. Workflow halted.",
                    force: true,
                    anchor: SoundManager.shared.contaminationAnchor
                )
                if !appModel.isHalted {
                    appModel.raiseContamination()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Detection. Contamination risk \(service.hasResult ? "\(Int(contaminationRisk * 100)) percent" : "not measured"). \(ppeText).")
        .onAppear { environment.start() }
    }

    private var header: some View {
        HStack {
            Text("DETECTION")
                .font(.system(size: panelWidth * 0.037, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if service.isLoading {
                Text("…")
                    .font(.system(size: panelWidth * 0.034, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
            } else if riskHigh {
                HStack(spacing: panelWidth * 0.017) {
                    Circle().fill(SPAIColor.warning).frame(width: panelWidth * 0.02, height: panelWidth * 0.02)
                    Text("RISK")
                        .font(.system(size: panelWidth * 0.034, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPAIColor.warning)
                }
                .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
            }
        }
    }

    private var contaminationRow: some View {
        HStack(spacing: panelWidth * 0.028) {
            Circle()
                .fill(riskHigh ? SPAIColor.warning : SPAIColor.safe)
                .frame(width: panelWidth * 0.028, height: panelWidth * 0.028)
                .shadow(color: (riskHigh ? SPAIColor.warning : SPAIColor.safe).opacity(0.8), radius: panelWidth * 0.011)
            Text("Contamination risk")
                .font(.system(size: panelWidth * 0.045, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            if service.hasResult {
                Text("\(Int(contaminationRisk * 100))%")
                    .font(.system(size: panelWidth * 0.057, weight: .bold, design: .monospaced))
                    .foregroundStyle(riskHigh ? SPAIColor.warning : SPAIColor.safe)
                    .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
            } else {
                Text("—")
                    .font(.system(size: panelWidth * 0.057, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
            }
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: panelWidth * 0.017) {
            Text("ENVIRONMENT (LIVE)")
                .font(.system(size: panelWidth * 0.034, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            if let temperatureF = environment.temperatureF {
                environmentRow(icon: "thermometer.medium", label: "Temperature",
                               value: "\(temperatureF)°F", ok: (68...73).contains(temperatureF))
            } else {
                environmentRow(icon: "thermometer.medium", label: "Temperature",
                               value: environment.errorMessage == nil ? "…" : "—", ok: true)
            }
            if let humidityPct = environment.humidityPct {
                environmentRow(icon: "humidity.fill", label: "Humidity",
                               value: "\(humidityPct)%", ok: (30...60).contains(humidityPct))
            } else {
                environmentRow(icon: "humidity.fill", label: "Humidity",
                               value: environment.errorMessage == nil ? "…" : "—", ok: true)
            }
            environmentRow(icon: "wind", label: "Air pressure",
                           value: positivePressure ? "Positive" : "Negative", ok: positivePressure)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Environment. Temperature \(environment.temperatureF.map(String.init) ?? "unavailable") degrees. Humidity \(environment.humidityPct.map(String.init) ?? "unavailable") percent. Air pressure \(positivePressure ? "positive" : "negative").")
    }

    private func environmentRow(icon: String, label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: panelWidth * 0.028) {
            Circle().fill(ok ? SPAIColor.safe : SPAIColor.warning).frame(width: panelWidth * 0.023, height: panelWidth * 0.023)
            Image(systemName: icon)
                .font(.system(size: panelWidth * 0.04))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: panelWidth * 0.051)
            Text(label)
                .font(.system(size: panelWidth * 0.04))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            Text(value)
                .font(.system(size: panelWidth * 0.04, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
    }

    private var ppeRow: some View {
        HStack(spacing: panelWidth * 0.023) {
            Image(systemName: ppePassing ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: panelWidth * 0.043))
                .foregroundStyle(ppePassing ? SPAIColor.safe : SPAIColor.warning)
            Text(ppeText)
                .font(.system(size: panelWidth * 0.04))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            Text("glove · hand")
                .font(.system(size: panelWidth * 0.034, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(minWidth: 44, minHeight: max(44, panelWidth * 0.13))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
    }
}

#Preview {
    DetectionPanel(service: DetectionService(), panelWidth: 350)
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
