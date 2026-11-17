//
//  DetectionPanel.swift
//  SPAI
//

import SwiftUI

/// What SPAI can see right now, answered in the order a tech needs it:
/// are my hands safe, what am I holding, is the room in range.
///
/// Each answer is one line. Detail — inspection checks, individual room
/// readings — is a tap away, and opens by itself only when something is
/// actually wrong.
struct DetectionPanel: View {
    @Environment(AppModel.self) private var appModel
    let service: DetectionService
    private let environment = EnvironmentService.shared

    private let positivePressure = true

    @State private var showRoomDetail = false
    @State private var showChecks = false

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

    // MARK: Hands

    private enum HandState {
        case waiting, gloved, bare, none
    }

    private var handState: HandState {
        guard service.hasResult else { return .waiting }
        if riskHigh { return .bare }
        if ppePassing { return .gloved }
        return .none
    }

    private var handTitle: String {
        switch handState {
        case .waiting: return "No camera feed"
        case .gloved:  return "Gloves on"
        case .bare:    return "Bare hand visible"
        case .none:    return "No hands in view"
        }
    }

    private var handDetail: String {
        switch handState {
        case .waiting: return appModel.cameraNote ?? "SPAI isn't receiving video yet."
        case .gloved:  return "Contamination risk low"
        case .bare:    return "Contamination risk high"
        case .none:    return "Hold your hands in view of the camera"
        }
    }

    private var handIcon: String {
        switch handState {
        case .waiting: return "camera.viewfinder"
        case .gloved:  return "checkmark.shield.fill"
        case .bare:    return "exclamationmark.triangle.fill"
        case .none:    return "hand.raised.slash"
        }
    }

    private var handColor: Color {
        switch handState {
        case .waiting, .none: return SPAIText.secondary
        case .gloved:         return SPAIColor.safe
        case .bare:           return SPAIColor.critical
        }
    }

    // MARK: Room

    private var temperatureOK: Bool {
        environment.temperatureF.map { (68...73).contains($0) } ?? true
    }

    private var humidityOK: Bool {
        environment.humidityPct.map { (30...60).contains($0) } ?? true
    }

    private var roomOK: Bool { temperatureOK && humidityOK && positivePressure }

    private var roomSummary: String {
        guard roomOK else { return "Room out of range" }
        var parts: [String] = []
        if let temperature = environment.temperatureF { parts.append("\(temperature)°F") }
        if let humidity = environment.humidityPct { parts.append("\(humidity)%") }
        return parts.isEmpty ? "Room conditions" : "Room OK · " + parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header
            handsRow
            if handState == .waiting {
                noFeedHelp
            }

            if let instrument = service.identifiedInstrument {
                divider
                instrumentSection(instrument)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider
            roomSection
        }
        .padding(SPAISpacing.l)
        .frame(width: 330, alignment: .leading)
        .spaiPanel(PanelID.detection, border: borderState)
        .animation(.easeInOut(duration: 0.4), value: riskHigh)
        .animation(.easeInOut(duration: 0.3), value: service.identifiedInstrument)
        .animation(.easeInOut(duration: 0.25), value: showRoomDetail)
        .animation(.easeInOut(duration: 0.25), value: showChecks)
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
        .onChange(of: service.identifiedInstrument?.key) { _, _ in
            // A different instrument starts collapsed again.
            showChecks = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detection. \(handTitle). Contamination risk \(service.hasResult ? "\(Int(contaminationRisk * 100)) percent" : "not measured"). \(ppeText).")
        .onAppear { environment.start() }
    }

    private var header: some View {
        PanelHeader("Detection", icon: "viewfinder", tint: riskHigh ? SPAIColor.critical : SPAIColor.primary) {
            if riskHigh {
                SPAIChip(text: "RISK", tint: SPAIColor.critical, live: true)
                    .id("risk")
            } else if service.hasResult {
                SPAIChip(text: "LIVE", tint: SPAIColor.safe, live: true)
                    .id("live")
            } else if service.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking")
            }
        }
    }

    private var riskColor: Color {
        switch borderState {
        case .critical:          return SPAIColor.critical
        case .warning:           return SPAIColor.warning
        case .normal, .attention: return SPAIColor.safe
        }
    }

    private var handsRow: some View {
        HStack(spacing: SPAISpacing.m) {
            RiskGauge(value: contaminationRisk, color: riskColor,
                      hasValue: service.hasResult && handState != .none)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(handTitle)
                } icon: {
                    Image(systemName: handIcon)
                        .foregroundStyle(handColor)
                }
                .font(SPAIFont.headline)
                .foregroundStyle(SPAIText.primary)
                Text(handDetail)
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Shown when no video is arriving. "Waiting" told a first-time user
    /// nothing; this says what to do about it.
    private var noFeedHelp: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Text("Guidance still works. To turn on checks, connect a camera or try it with a photo.")
                .font(SPAIFont.caption)
                .foregroundStyle(SPAIText.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                appModel.panelVisibility[PanelID.upload] = true
            } label: {
                Label("Open Test Media", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.spai(.tinted(SPAIColor.secondary)))
        }
    }

    // MARK: Instrument

    private func instrumentSection(_ instrument: IdentifiedInstrument) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            HStack(alignment: .top, spacing: SPAISpacing.s + 4) {
                Image(systemName: instrument.info?.icon ?? "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(instrument.certain ? SPAIColor.primaryBright : SPAIText.secondary)
                    .frame(width: 40, height: 40)
                    .background((instrument.certain ? SPAIColor.primary : Color.white).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(instrument.held ? "You're holding" : "In view")
                        .spaiEyebrow(SPAIColor.primaryBright)
                    Text(instrument.certain ? instrument.name : "An instrument")
                        .font(SPAIFont.bodyStrong)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(instrument.info?.summary ?? "Not sure which one — hold it flat and a little closer.")
                        .font(SPAIFont.caption)
                        .foregroundStyle(SPAIText.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if instrument.certain {
                    SPAIChip(text: "\(instrument.confidencePercent)%", tint: SPAIColor.primaryBright)
                        .accessibilityLabel("\(instrument.confidencePercent) percent confident")
                }
            }

            if let info = instrument.info {
                disclosureButton(showChecks ? "Hide checks" : "What to check", isOpen: showChecks) {
                    showChecks.toggle()
                }
                if showChecks {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(info.inspect, id: \.self) { check in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(SPAIColor.safe)
                                    .padding(.top, 2)
                                Text(check)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text(info.handling)
                            .font(SPAIFont.caption)
                            .foregroundStyle(SPAIText.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    .transition(.opacity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(instrument.certain
            ? "Instrument: \(instrument.name). \(instrument.info?.summary ?? "")"
            : "An instrument is in view, but SPAI is not sure which one.")
    }

    // MARK: Room

    private var roomSection: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s) {
            Button {
                showRoomDetail.toggle()
            } label: {
                HStack(spacing: 10) {
                    LiveDot(color: roomOK ? SPAIColor.safe : SPAIColor.warning, size: 8, animating: !roomOK)
                        .id(roomOK)
                    Text(roomSummary)
                        .font(SPAIFont.label)
                        .foregroundStyle(SPAIText.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SPAIText.tertiary)
                        .rotationEffect(.degrees(showRoomDetail || !roomOK ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityLabel("\(roomSummary). \(showRoomDetail ? "Hide" : "Show") room readings")

            // Opens on its own when a reading is out of range.
            if showRoomDetail || !roomOK {
                VStack(spacing: SPAISpacing.s) {
                    environmentRow(icon: "thermometer.medium", label: "Temperature",
                                   value: environment.temperatureF.map { "\($0)°F" }
                                       ?? (environment.errorMessage == nil ? "…" : "—"),
                                   ok: temperatureOK)
                    environmentRow(icon: "humidity.fill", label: "Humidity",
                                   value: environment.humidityPct.map { "\($0)%" }
                                       ?? (environment.errorMessage == nil ? "…" : "—"),
                                   ok: humidityOK)
                    environmentRow(icon: "wind", label: "Air pressure",
                                   value: positivePressure ? "Positive" : "Negative", ok: positivePressure)
                }
                .padding(12)
                .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Temperature \(environment.temperatureF.map(String.init) ?? "unavailable") degrees. Humidity \(environment.humidityPct.map(String.init) ?? "unavailable") percent. Air pressure \(positivePressure ? "positive" : "negative").")
            }
        }
    }

    private func environmentRow(icon: String, label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ok ? SPAIColor.primaryBright : SPAIColor.warning)
                .frame(width: 20)
            Text(label)
                .font(SPAIFont.label)
                .foregroundStyle(SPAIText.primary)
            Spacer()
            Text(value)
                .font(SPAIFont.value)
                .foregroundStyle(ok ? SPAIText.primary : SPAIColor.warning)
            Circle()
                .fill(ok ? SPAIColor.safe : SPAIColor.warning)
                .frame(width: 7, height: 7)
                .shadow(color: (ok ? SPAIColor.safe : SPAIColor.warning).opacity(0.8), radius: 3)
        }
    }

    private func disclosureButton(_ title: String, isOpen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(SPAIFont.label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundStyle(SPAIColor.primaryBright)
        }
        .buttonStyle(.plain)
        .spaiHitTarget()
    }

    private var divider: some View {
        SPAIDivider()
    }
}

/// Circular contamination-risk meter.
struct RiskGauge: View {
    let value: Double
    let color: Color
    let hasValue: Bool
    var lineWidth: CGFloat = 10

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
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if hasValue {
                        Text("%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(hasValue ? color : SPAIText.tertiary)
                Text("risk")
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(SPAIText.tertiary)
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
