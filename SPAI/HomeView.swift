//
//  HomeView.swift
//  SPAI
//

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false

    @State private var appeared = false

    private var isOpening: Bool { appModel.immersiveSpaceState == .inTransition }

    private var guidedCheckCount: Int {
        SterileStep.allCases.reduce(0) { $0 + StationScripts.script(for: $1).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            Spacer(minLength: 16)

            HStack(alignment: .center, spacing: 32) {
                hero
                Spacer(minLength: 0)
                logoStage
            }

            Spacer(minLength: 24)

            featureRow

            Spacer(minLength: 18)

            statsStrip
        }
        .padding(.horizontal, 52)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .spaiWindowBackground()
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            SterileNodeMark(size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("SPAI")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SPAIColor.textPrimary)
                Text("Sterile Processing AI")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SPAIColor.textTertiary)
            }
            Spacer()
            StatusPill(text: "Prototype", systemImage: "sparkles", color: SPAIColor.secondary)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sterile processing assistant")
                .spaiEyebrow(SPAIColor.primaryBright)

            VStack(alignment: .leading, spacing: 0) {
                Text("Sterile prep,")
                    .foregroundStyle(SPAIColor.textPrimary)
                Text("guided by AI.")
                    .foregroundStyle(SPAIGradient.aurora)
            }
            .font(.system(size: 52, weight: .bold))
            .tracking(-1.1)

            Text("SPAI checks PPE, confirms each step, and flags contamination risk in real time — right in the space around you.")
                .font(.system(size: 18))
                .foregroundStyle(SPAIColor.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                enterButton

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        alwaysShowOnboarding = true
                    }
                } label: {
                    Label("Take the tour", systemImage: "rectangle.stack.fill")
                }
                .buttonStyle(.spai(.glass, size: .large))
                .disabled(isOpening)
            }
            .padding(.top, 6)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private var enterButton: some View {
        Button {
            Task { await enterWorkspace() }
        } label: {
            HStack(spacing: 12) {
                if isOpening {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(isOpening ? "Opening workspace…" : "Begin Sterile Prep")
            }
        }
        .buttonStyle(.spai(.primary, size: .large))
        .disabled(isOpening)
        .accessibilityHint("Opens the immersive sterile prep workspace")
    }

    private var logoStage: some View {
        VStack(spacing: 16) {
            InteractiveLogo(size: 232)
            Text("Look at it · tap to scan")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SPAIColor.textTertiary)
        }
        .frame(width: 290)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
    }

    // MARK: - Features

    private var featureRow: some View {
        HStack(spacing: 16) {
            ForEach(features.indices, id: \.self) { index in
                let feature = features[index]
                FeatureCard(
                    title: feature.title,
                    subtitle: feature.subtitle,
                    icon: feature.icon,
                    tint: feature.tint,
                    footnote: feature.footnote
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(
                    .spring(response: 0.7, dampingFraction: 0.85).delay(0.12 + Double(index) * 0.08),
                    value: appeared
                )
            }
        }
    }

    private var features: [HomeFeature] {
        [
            HomeFeature(
                title: "Guided Workflow",
                subtitle: "Five stations with step-by-step voice guidance",
                icon: "checklist.checked",
                tint: SPAIColor.primary,
                footnote: "\(SterileStep.allCases.count) stations · \(guidedCheckCount) checks"
            ),
            HomeFeature(
                title: "AI Vision",
                subtitle: "Live glove, bare-hand and instrument detection",
                icon: "viewfinder",
                tint: SPAIColor.secondary,
                footnote: "Cloud + on-device"
            ),
            HomeFeature(
                title: "Contamination Guard",
                subtitle: "A bare hand during a sterile step halts the workflow",
                icon: "exclamationmark.shield.fill",
                tint: SPAIColor.critical,
                footnote: "Instant alerts"
            )
        ]
    }

    private var statsStrip: some View {
        HStack(spacing: 22) {
            stat(icon: "square.stack.3d.up.fill", text: "\(SterileStep.allCases.count) stations")
            stat(icon: "checklist", text: "\(guidedCheckCount) guided checks")
            stat(icon: "checkmark.shield.fill", text: "3-frame AI verification")
            stat(icon: "cpu", text: "On-device fallback")
            Spacer()
        }
        .opacity(appeared ? 1 : 0)
    }

    private func stat(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SPAIColor.primary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SPAIColor.textTertiary)
        }
    }

    // MARK: - Actions

    private func enterWorkspace() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition

        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            appModel.immersiveSpaceState = .open
            dismissWindow(id: "home")
        case .error, .userCancelled:
            appModel.immersiveSpaceState = .closed
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}

private struct HomeFeature {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let footnote: String
}

#Preview {
    HomeView()
        .environment(AppModel())
        .frame(width: 1040, height: 720)
}
