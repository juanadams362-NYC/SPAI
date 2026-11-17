//
//  OnboardingView.swift
//  SPAI
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false

    @State private var page = 0
    private let totalPages = 5

    private var isLastPage: Bool { page == totalPages - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 12)

            ZStack {
                pageContent
                    .id(page)
                    .transition(
                        AnyTransition.asymmetric(
                            insertion: AnyTransition.opacity.combined(with: AnyTransition.offset(x: 36)),
                            removal: AnyTransition.opacity.combined(with: AnyTransition.offset(x: -36))
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 12)

            navigationControls
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .spaiWindowBackground()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            SterileNodeMark(size: 36)
            Text("SPAI")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SPAIColor.textPrimary)
            Spacer()
            if !isLastPage {
                Button("Skip intro") { finish() }
                    .buttonStyle(.spai(.ghost, size: .small))
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:
            pageLayout(
                eyebrow: "Welcome",
                title: "Your spatial assistant\nfor sterile prep.",
                message: "SPAI watches your workflow, checks PPE and compliance, and guides you step by step — all in the room around you.",
                points: []
            ) {
                VStack(spacing: 18) {
                    InteractiveLogo(size: 250)
                    Text("Look at the logo · tap it to scan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SPAIColor.textTertiary)
                }
            }
        case 1:
            pageLayout(
                eyebrow: "Your workspace",
                title: "Panels around you",
                message: "Your workspace floats in a comfortable arc, so everything is one glance away.",
                points: [
                    OnboardingPoint(icon: "rectangle.3.group", title: "Status bar · top",
                                    detail: "Session time, role, station and detection mode"),
                    OnboardingPoint(icon: "viewfinder", title: "Detection · left",
                                    detail: "Live PPE check, contamination risk and environment"),
                    OnboardingPoint(icon: "waveform.path.ecg", title: "Event log · right",
                                    detail: "A real-time feed of workflow events and alerts"),
                    OnboardingPoint(icon: "checklist", title: "Workflow · bottom",
                                    detail: "All five stations and where you are")
                ]
            ) {
                PanelArcDiagram()
            }
        case 2:
            pageLayout(
                eyebrow: "AI vision",
                title: "Live detection",
                message: "SPAI continuously watches your hands and instruments:",
                points: [
                    OnboardingPoint(icon: "hand.raised.fill", title: "PPE compliance",
                                    detail: "Tells gloved hands from bare hands in real time"),
                    OnboardingPoint(icon: "exclamationmark.triangle.fill", title: "Contamination risk",
                                    detail: "Bare skin during a sterile step halts the workflow"),
                    OnboardingPoint(icon: "tray.full.fill", title: "Instrument detection",
                                    detail: "Confirms trays are loaded before you move on"),
                    OnboardingPoint(icon: "clock.arrow.circlepath", title: "Auto-advance",
                                    detail: "Moves on after 3 consecutive confirmations")
                ]
            ) {
                DetectionDemoVisual()
            }
        case 3:
            pageLayout(
                eyebrow: "Guided workflow",
                title: "Five stations,\nguided.",
                message: "Tap Start Step and SPAI speaks each instruction, then watches for completion. For manual steps, just say \"done\".",
                points: []
            ) {
                StationTimeline()
            }
        default:
            pageLayout(
                eyebrow: "Test anywhere",
                title: "Try it without a tray",
                message: "In the Test Detection panel you can:",
                points: [
                    OnboardingPoint(icon: "photo.badge.plus", title: "Upload test media",
                                    detail: "Run detection on images or videos from your library"),
                    OnboardingPoint(icon: "iphone", title: "Use your iPhone camera",
                                    detail: "Stream live frames with Continuity Camera on device"),
                    OnboardingPoint(icon: "slider.horizontal.3", title: "Tune settings",
                                    detail: "Panel opacity, billboarding and confidence threshold")
                ]
            ) {
                TestLabVisual()
            }
        }
    }

    private func pageLayout<Visual: View>(
        eyebrow: String,
        title: String,
        message: String,
        points: [OnboardingPoint],
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        HStack(alignment: .center, spacing: 44) {
            VStack(alignment: .leading, spacing: 16) {
                Text(eyebrow)
                    .spaiEyebrow(SPAIColor.primaryBright)

                Text(title)
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(SPAIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(SPAIColor.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !points.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(points, id: \.title) { point in
                            pointRow(point)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            visual()
                .frame(width: 360, height: 380)
        }
    }

    private func pointRow(_ point: OnboardingPoint) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: point.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SPAIColor.primaryBright)
                .frame(width: 34, height: 34)
                .background(SPAIColor.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(point.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text(point.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(SPAIColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        HStack {
            Button {
                go(to: page - 1)
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.spai(.ghost))
            .opacity(page > 0 ? 1 : 0)
            .disabled(page == 0)

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == page
                              ? AnyShapeStyle(SPAIGradient.brand)
                              : AnyShapeStyle(Color.white.opacity(index < page ? 0.5 : 0.2)))
                        .frame(width: index == page ? 30 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(totalPages)")

            Spacer()

            Button {
                if isLastPage {
                    finish()
                } else {
                    go(to: page + 1)
                }
            } label: {
                Label(isLastPage ? "Get Started" : "Next",
                      systemImage: isLastPage ? "checkmark" : "arrow.right")
            }
            .buttonStyle(.spai(.primary))
        }
    }

    private func go(to newPage: Int) {
        guard (0..<totalPages).contains(newPage) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
            page = newPage
        }
    }

    private func finish() {
        alwaysShowOnboarding = false
        appModel.hasCompletedOnboarding = true
    }
}

private struct OnboardingPoint {
    let icon: String
    let title: String
    let detail: String
}

// MARK: - Page visuals

/// A miniature of the immersive layout. The side panels are really rotated in 3D, so on
/// device they angle toward you like the real arc.
private struct PanelArcDiagram: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            Ellipse()
                .strokeBorder(SPAIColor.primary.opacity(0.25), lineWidth: 1.5)
                .frame(width: 330, height: 96)
                .offset(y: 132)

            block("Status bar", icon: "rectangle.3.group", width: 250, height: 34)
                .offset(y: -150)

            block("Detection", icon: "viewfinder", width: 104, height: 128)
                .rotation3DEffect(.degrees(28), axis: (x: 0, y: 1, z: 0))
                .offset(x: -122, y: -32)

            block("Event log", icon: "waveform.path.ecg", width: 104, height: 128)
                .rotation3DEffect(.degrees(-28), axis: (x: 0, y: 1, z: 0))
                .offset(x: 122, y: -32)

            block("Guided", icon: "text.bubble.fill", width: 112, height: 70, tint: SPAIColor.secondary)
                .offset(x: 30, y: 54)

            block("Workflow", icon: "checklist", width: 220, height: 40)
                .offset(y: 118)

            VStack(spacing: 4) {
                Circle()
                    .fill(SPAIGradient.brand)
                    .frame(width: 14, height: 14)
                    .shadow(color: SPAIColor.primaryBright.opacity(glow ? 0.9 : 0.3), radius: glow ? 10 : 4)
                Text("YOU")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(SPAIColor.textTertiary)
            }
            .offset(y: 170)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .accessibilityHidden(true)
    }

    private func block(_ title: String, icon: String, width: CGFloat, height: CGFloat,
                       tint: Color = SPAIColor.primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            if height > 60 {
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 5)
                    Capsule().fill(Color.white.opacity(0.12)).frame(width: width * 0.5, height: 5)
                    Capsule().fill(Color.white.opacity(0.12)).frame(width: width * 0.65, height: 5)
                }
            }
        }
        .padding(10)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color(hex: 0x0B1626).opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [tint.opacity(0.7), SPAIColor.secondary.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2
                )
        }
        .shadow(color: tint.opacity(0.25), radius: 10)
    }
}

/// A gloved hand (green box) next to a bare hand (rose box) with a scan beam sweeping.
private struct DetectionDemoVisual: View {
    @State private var beamDown = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hex: 0x0B1626).opacity(0.7))
                .overlay {
                    GridPattern(spacing: 30)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(SPAIColor.hairline, lineWidth: 1)
                }

            detectionTarget(color: SPAIColor.safe, label: "glove 96%", handTint: SPAIColor.secondary, size: 92)
                .offset(x: -78, y: 10)

            detectionTarget(color: SPAIColor.critical, label: "hand 91%", handTint: Color.white.opacity(0.85), size: 80)
                .offset(x: 86, y: -18)

            ScanBeam(width: 300)
                .offset(y: beamDown ? 140 : -140)

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    SPAIChip(text: "PPE check", icon: "checkmark.seal.fill", tint: SPAIColor.safe)
                    SPAIChip(text: "Risk 85%", icon: "exclamationmark.triangle.fill", tint: SPAIColor.critical)
                }
                .padding(.bottom, 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                beamDown = true
            }
        }
        .accessibilityHidden(true)
    }

    private func detectionTarget(color: Color, label: String, handTint: Color, size: CGFloat) -> some View {
        Image(systemName: "hand.raised.fill")
            .font(.system(size: size))
            .foregroundStyle(handTint)
            .padding(16)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color, lineWidth: 2.5)
                    .shadow(color: color.opacity(0.7), radius: 6)
            }
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SPAIColor.onFill)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(y: -22)
            }
    }
}

/// The five stations as a vertical timeline.
private struct StationTimeline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SterileStep.allCases) { step in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(SPAIColor.primary.opacity(0.16))
                        Circle()
                            .strokeBorder(SPAIColor.primary.opacity(0.5), lineWidth: 1.5)
                        Image(systemName: step.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SPAIColor.primaryBright)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(step.rawValue + 1)  \(step.title)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SPAIColor.textPrimary)
                        Text(step.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(SPAIColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if step != SterileStep.allCases.last {
                    Rectangle()
                        .fill(LinearGradient(colors: [SPAIColor.primary.opacity(0.6), SPAIColor.secondary.opacity(0.4)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2, height: 12)
                        .padding(.leading, 36)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A test image card with detection boxes and confidence bars.
private struct TestLabVisual: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color(hex: 0x1E3A5F), Color(hex: 0x2A1E4F)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.white.opacity(0.18))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(SPAIColor.safe, lineWidth: 2)
                    .frame(width: 110, height: 80)
                    .offset(x: -60, y: 8)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(SPAIColor.primary, lineWidth: 2)
                    .frame(width: 96, height: 58)
                    .offset(x: 72, y: -18)
            }
            .frame(height: 170)

            resultRow(name: "Glove", confidence: 0.96, color: SPAIColor.safe)
            resultRow(name: "Instrument", confidence: 0.88, color: SPAIColor.primary)
            resultRow(name: "Instrument", confidence: 0.74, color: SPAIColor.primary)
        }
        .padding(18)
        .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(SPAIColor.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func resultRow(name: String, confidence: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SPAIColor.textPrimary)
                .frame(width: 90, alignment: .leading)
            ConfidenceBar(value: confidence, color: color)
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(SPAIColor.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// Thin capsule meter for detection confidence.
struct ConfidenceBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: 6)
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
        .frame(width: 1040, height: 680)
}
