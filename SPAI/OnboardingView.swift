//
//  OnboardingView.swift
//  SPAI
//
//  Created by Juan Adams on 6/7/26.
//


//
//  OnboardingView.swift
//  SPAI
//
//  First-launch guided walkthrough. Not an account flow — it introduces
//  what SPAI does, then lets the user set their per-panel display modes
//  before entering the workspace. Shown until onboarding is completed.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel

    // Which page of the walkthrough we're on.
    @State private var page = 0

    // The panels the user can configure, with friendly names.
    private let configurablePanels: [(id: String, name: String)] = [
        ("statusBar", "Status Bar"),
        ("workflow", "Workflow Progress"),
        ("compliance", "Compliance"),
        ("eventLog", "Event Log"),
        ("actions", "Quick Actions")
    ]

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: SPAISpacing.xl) {
                // Page content.
                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: howItWorksPage
                    default: settingsPage
                    }
                }
                .frame(maxWidth: 620)

                Spacer()

                navigationControls
            }
            .padding(SPAISpacing.xxl)
        }
    }

    // MARK: - Page 0: welcome

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Image(systemName: "visionpro")
                .font(.system(size: 56))
                .foregroundStyle(SPAIColor.primary)

            Text("Welcome to SPAI")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)

            Text("Your spatial assistant for sterile processing. SPAI watches your workflow, checks PPE and compliance, and guides you step by step — all floating in the room around you.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Page 1: how it works

    private var howItWorksPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("How it works")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            onboardingPoint(icon: "rectangle.3.group", title: "Floating panels",
                            detail: "Your workflow, compliance, and event log appear as panels around you.")
            onboardingPoint(icon: "hand.draw", title: "Always in view",
                            detail: "Panels turn to face you. You choose whether each one stays pinned or follows you.")
            onboardingPoint(icon: "checklist", title: "Guided steps",
                            detail: "SPAI tells you the current step, what's next, and flags any compliance issues.")
        }
    }

    private func onboardingPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: SPAISpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(SPAIColor.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    // MARK: - Page 2: settings (per-panel modes)

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("Set up your panels")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("Choose how each panel behaves. Pinned stays where you place it; Follows Me trails you as you move.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))

            VStack(spacing: SPAISpacing.s) {
                ForEach(configurablePanels, id: \.id) { panel in
                    panelModeRow(panel)
                }
            }
        }
    }

    private func panelModeRow(_ panel: (id: String, name: String)) -> some View {
        HStack {
            Text(panel.name)
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            // A segmented picker per panel, bound through AppModel.
            Picker("", selection: Binding(
                get: { appModel.mode(for: panel.id) },
                set: { appModel.setMode($0, for: panel.id) }
            )) {
                ForEach(PanelMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
        .padding(SPAISpacing.m)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        HStack {
            if page > 0 {
                Button("Back") {
                    withAnimation { page -= 1 }
                }
                .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Page dots.
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i == page ? SPAIColor.primary : .white.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            Button(page < 2 ? "Next" : "Get Started") {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    // Finish onboarding — the app moves on to HomeView.
                    appModel.hasCompletedOnboarding = true
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, SPAISpacing.l)
            .padding(.vertical, SPAISpacing.m)
            .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
}
