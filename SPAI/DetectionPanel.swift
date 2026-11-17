//
//  DetectionPanel.swift
//  SPAI
//

import SwiftUI

struct DetectionPanel: View {
    @Environment(AppModel.self) private var appModel
    let service: DetectionService
    private let environment = EnvironmentService.shared

    private let positivePressure = true

    private var contaminationRisk: Double { service.contaminationRisk }
    private var ppePassing: Bool { service.ppePassing }
    private var riskHigh: Bool { contaminationRisk >= 0.5 }

    private var hasGlove: Bool {
        service.detections.contains { DetectionService.isGloveClass($0.className) }
    }
    private var hasHand: Bool {
        service.detections.contains { DetectionService.isHandClass($0.className) }
    }

    private var borderState: BorderState {
        if !service.hasResult { return .normal }
        if contaminationRisk >= 0.5 { return .critical }
        if contaminationRisk > 0.10 { return .warning }
        return .normal
    }

    private var riskColor: Color {
        switch borderState {
        case .critical: return SPAIColor.critical
        case .warning:  return SPAIColor.warning
        case .normal:   return SPAIColor.safe
        }
    }

    private var riskLevel: String {
        guard service.hasResult else { return "Not measured" }
        if riskHigh { return "High" }
        if contaminationRisk > 0.10 { return "Elevated" }
        return "Low"
    }

    private var riskDetail: String {
        guard service.hasResult else { return "Waiting for a camera feed" }
        if hasHand && !hasGlove { return "Bare hand in the sterile zone" }
        if hasGlove && hasHand { return "Glove and bare hand in view" }
        if hasGlove { return "Gloves detected" }
        return "No hands in view"
    }

    private var ppeText: String {
        service.hasResult ? (ppePassing ? "PPE check passing" : "PPE check failed") : "PPE check idle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            PanelHeader("Detection", icon: "viewfinder", tint: riskHigh ? SPAIColor.critical : SPAIColor.primary) {
                statusChip
            }
            riskHero
            ppeBanner
            environmentSection
        }
        .padding(SPAISpacing.l)
        .frame(width: 320, alignment: .leading)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(borderState, cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.easeInOut(duration: 0.4), value: riskHigh)
        .animation(.easeInOut(duration: 0.3), value: service.hasResult)
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

    // MARK: - Header chip

    @ViewBuilder
    private var statusChip: some View {
        if riskHigh {
            SPAIChip(text: "RISK", tint: SPAIColor.critical, live: true)
                .id("risk")
        } else if service.hasResult {
            SPAIChip(text: "LIVE", tint: SPAIColor.safe, live: true)
                .id("live")
        } else if service.isLoading {
            SPAIChip(text: "ANALYZING", tint: SPAIColor.primaryBright, live: true)
                .id("analyzing")
        } else {
            SPAIChip(text: "IDLE", icon: "pause.fill", tint: Color.white.opacity(0.6))
        }
    }

    // MARK: - Risk

    private var riskHero: some View {
        HStack(spacing: 18) {
            RiskGauge(value: contaminationRisk, color: riskColor, hasValue: service.hasResult)
                .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 6) {
                Text("Contamination risk")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SPAIColor.textTertiary)
                Text(riskLevel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(service.hasResult ? riskColor : SPAIColor.textSecondary)
                    .contentTransition(.opacity)
                Text(riskDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - PPE

    private var ppeTint: Color {
        guard service.hasResult else { return Color.white.opacity(0.7) }
        if hasHand && !hasGlove { return SPAIColor.critical }
        if hasGlove && hasHand { return SPAIColor.warning }
        if hasGlove { return SPAIColor.safe }
        return Color.white.opacity(0.7)
    }

    private var ppeIcon: String {
        guard service.hasResult else { return "hand.raised" }
        if ppePassing { return "checkmark.seal.fill" }
        if hasHand { return "exclamationmark.triangle.fill" }
        return "hand.raised"
    }

    private var ppeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: ppeIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ppeTint)
            Text(ppeText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SPAIColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("glove · hand")
                .font(SPAIFont.mono)
                .foregroundStyle(SPAIColor.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ppeTint.opacity(0.12), in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous)
                .strokeBorder(ppeTint.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(spacing: 6) {
                Text("Environment")
                    .spaiEyebrow()
                LiveDot(color: SPAIColor.primary, size: 5)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SPAIColor.primary)
            }
            HStack(spacing: 8) {
                MetricTile(
                    label: "Temp",
                    value: environment.temperatureF.map { "\($0)°F" } ?? placeholder,
                    icon: "thermometer.medium",
                    status: environment.temperatureF.map { (68...73).contains($0) ? SPAIColor.safe : SPAIColor.warning }
                )
                MetricTile(
                    label: "Humidity",
                    value: environment.humidityPct.map { "\($0)%" } ?? placeholder,
                    icon: "humidity.fill",
                    status: environment.humidityPct.map { (30...60).contains($0) ? SPAIColor.safe : SPAIColor.warning }
                )
                MetricTile(
                    label: "Air",
                    value: positivePressure ? "Positive" : "Negative",
                    icon: "wind",
                    status: positivePressure ? SPAIColor.safe : SPAIColor.warning
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Environment. Temperature \(environment.temperatureF.map(String.init) ?? "unavailable") degrees. Humidity \(environment.humidityPct.map(String.init) ?? "unavailable") percent. Air pressure \(positivePressure ? "positive" : "negative").")
    }

    private var placeholder: String {
        environment.errorMessage == nil ? "…" : "—"
    }
}

/// Circular contamination-risk meter.
struct RiskGauge: View {
    let value: Double
    let color: Color
    let hasValue: Bool
    var lineWidth: CGFloat = 11

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: hasValue ? CGFloat(max(min(value, 1), 0.03)) : 0)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.55), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(min(value, 1), 0.03))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 6)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(hasValue ? "\(Int(value * 100))" : "—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if hasValue {
                        Text("%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(hasValue ? color : SPAIColor.textTertiary)
                Text("risk")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(SPAIColor.textTertiary)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: hasValue)
    }
}

#Preview {
    DetectionPanel(service: DetectionService())
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
