//
//  OnboardingView.swift
//  SPAI
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("alwaysShowOnboarding") private var alwaysShowOnboarding = false

    @State private var page = 0

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: SPAISpacing.xl) {
                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: howItWorksPage
                    default: stationsPage
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

            Text("Your spatial assistant for sterile processing. SPAI watches your workflow, checks PPE and compliance, and guides you step by step — all in the room around you.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Page 1: how it works

    private var howItWorksPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("How it works")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            onboardingPoint(icon: "rectangle.3.group", title: "Panels around you",
                            detail: "Your workflow, detection, and event log appear as panels at the edges of your view, keeping the center clear for your hands and the tray.")
            onboardingPoint(icon: "viewfinder", title: "Live detection",
                            detail: "SPAI watches for PPE and contamination risk as you work, and flags issues in real time.")
            onboardingPoint(icon: "checklist", title: "Guided steps",
                            detail: "SPAI tracks the current sterile-processing step, what's next, and enforces the correct order.")
        }
    }

    // MARK: - Page 2: stations

    private var stationsPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("Walk between stations")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("SPAI follows the real layout of your department. When you move to a station — decontamination, inspection, assembly, packaging, or seal validation — SPAI loads that step's workspace around you.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))

            onboardingPoint(icon: "figure.walk", title: "Move to begin",
                            detail: "Step into a station's area and SPAI sets the workflow to that step automatically.")
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
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

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
                    alwaysShowOnboarding = false
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
