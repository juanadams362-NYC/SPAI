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

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: SPAISpacing.xl) {
                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: panelsPage
                    case 2: detectionPage
                    case 3: workflowPage
                    case 4: testingPage
                    default: welcomePage
                    }
                }
                .frame(maxWidth: 700)

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
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Page 1: Panels

    private var panelsPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("Panels Around You")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("Your workspace includes several floating panels positioned in a comfortable arc:")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: SPAISpacing.m) {
                onboardingPoint(icon: "rectangle.3.group", title: "Status Bar (Top)",
                                detail: "Shows session time, your role, detection mode, and quick actions")
                onboardingPoint(icon: "viewfinder", title: "Detection (Left)",
                                detail: "Live PPE check, contamination risk, and environment stats")
                onboardingPoint(icon: "waveform.path.ecg", title: "Event Log (Right)",
                                detail: "Real-time feed of workflow events and alerts")
                onboardingPoint(icon: "checklist", title: "Workflow Progress (Bottom)",
                                detail: "Shows all 5 steps and your current position")
            }
        }
    }

    // MARK: - Page 2: Detection

    private var detectionPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("Live Detection")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("SPAI continuously monitors for:")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: SPAISpacing.m) {
                onboardingPoint(icon: "hand.raised.fill", title: "PPE Compliance",
                                detail: "Detects gloves vs. bare hands in real-time")
                onboardingPoint(icon: "exclamationmark.triangle.fill", title: "Contamination Risk",
                                detail: "Alerts when bare skin is detected during sterile steps")
                onboardingPoint(icon: "tray.full.fill", title: "Instrument Detection",
                                detail: "Verifies surgical trays are loaded correctly")
                onboardingPoint(icon: "clock.arrow.circlepath", title: "Auto-Advance",
                                detail: "Moves to next step after 3 consecutive successful detections")
            }
        }
    }

    // MARK: - Page 3: Workflow

    private var workflowPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("Guided Workflow")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("SPAI guides you through all 5 sterile processing steps:")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: SPAISpacing.s + 2) {
                stepRow("1", "Decontamination", "Remove visible soil")
                stepRow("2", "Inspection", "Check for damage")
                stepRow("3", "Tray Assembly", "Organize instruments")
                stepRow("4", "Packaging", "Prepare for sterilization")
                stepRow("5", "Seal Validation", "Verify packaging integrity")
            }

            Text("Tap 'Start Step' to begin. SPAI will give voice instructions and watch for completion.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Page 4: Testing

    private var testingPage: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("Testing Features")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Text("In the 'SIM TEST' panel, you can:")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: SPAISpacing.m) {
                onboardingPoint(icon: "photo.badge.plus", title: "Upload Test Media",
                                detail: "Test detection with images or videos from your library")
                onboardingPoint(icon: "iphone", title: "Use iPhone Camera (Real Device)",
                                detail: "Connect your iPhone via Continuity Camera for live testing")
                onboardingPoint(icon: "slider.horizontal.3", title: "Adjust Settings",
                                detail: "Change panel opacity, billboard mode, and confidence thresholds")
            }

            Text("Ready to begin your spatial sterile processing journey!")
                .font(.title3.bold())
                .foregroundStyle(SPAIColor.primary)
        }
    }

    private func stepRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: SPAISpacing.m) {
            Text(number)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SPAIColor.primary)
                .frame(width: 28, height: 28)
                .background(SPAIColor.primary.opacity(0.2), in: Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Navigation

    private var navigationControls: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .foregroundStyle(.white.opacity(0.7))
                    .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { i in                    Circle()
                        .fill(i == page ? SPAIColor.primary : .white.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            Button(page < totalPages - 1 ? "Next" : "Get Started") {
                if page < totalPages - 1 {
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
