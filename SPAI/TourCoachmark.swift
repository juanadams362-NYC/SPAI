//
//  TourCoachmark.swift
//  SPAI
//
//  The card the guided tour speaks through.
//

import SwiftUI

/// A single floating card that moves to whichever panel the tour is currently talking about.
///
/// Deliberately *not* a full-screen dimming overlay. In an immersive space a dimmed backdrop is
/// a large opaque plane hanging in the room — it hides the very workspace the tour is meant to
/// explain, and it makes the app feel like it has stopped. The card sits beside its subject
/// instead, and the rest of the app stays live and tappable the entire time.
struct TourCoachmark: View {
    @Environment(AppModel.self) private var appModel

    private var tour: AppTour { appModel.tour }

    var body: some View {
        Group {
            switch tour.phase {
            case .idle:
                EmptyView()
            case .offered:
                offerCard
            case .running:
                if let step = tour.currentStep { stepCard(step) }
            case .finished:
                finishedCard
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tour.stepIndex)
        .animation(.easeInOut(duration: 0.25), value: tour.phase)
    }

    // MARK: - Offer

    private var offerCard: some View {
        card {
            VStack(alignment: .leading, spacing: SPAISpacing.m) {
                header(title: "Want a quick tour?", badge: nil)

                Text("Two minutes. It walks you through the panels, the workflow, and the wrist menu while you actually use them. You can stop at any point.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SPAISpacing.m) {
                    secondaryButton("No thanks") {
                        appModel.completeTour()
                        tour.finish()
                    }
                    Spacer()
                    primaryButton("Show me") {
                        tour.start(wristMenusEnabled: appModel.wristMenusEnabled)
                    }
                }
            }
        }
    }

    // MARK: - Step

    private func stepCard(_ step: TourStep) -> some View {
        card {
            VStack(alignment: .leading, spacing: SPAISpacing.m) {
                header(
                    title: step.title,
                    badge: "\(tour.progress.current) of \(tour.progress.total)"
                )

                Text(step.message)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)

                progressDots

                HStack(spacing: SPAISpacing.m) {
                    if tour.stepIndex > 0 {
                        secondaryButton("Back") { tour.back() }
                    }
                    secondaryButton("Skip tour") {
                        appModel.completeTour()
                        tour.skip()
                    }

                    Spacer()

                    if let cta = step.callToAction, step.advanceOn != nil {
                        // Waiting on the user to do the real thing. "Next" is still offered
                        // so nobody can get stuck on an action they can't perform.
                        HStack(spacing: SPAISpacing.s) {
                            waitingPrompt(cta)
                            secondaryButton("Next") { tour.next() }
                        }
                    } else {
                        primaryButton(tour.stepIndex == tour.steps.count - 1 ? "Finish" : "Next") {
                            tour.next()
                        }
                    }
                }
            }
        }
    }

    /// Pulses while the tour waits, and flips to a confirmation the moment the user does it.
    private func waitingPrompt(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tour.justSatisfied ? "checkmark.circle.fill" : "hand.tap.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(tour.justSatisfied ? "Nice." : text)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
        }
        .foregroundStyle(tour.justSatisfied ? SPAIColor.safe : SPAIColor.accent)
        .padding(.horizontal, SPAISpacing.m)
        .padding(.vertical, SPAISpacing.s)
        .background(
            (tour.justSatisfied ? SPAIColor.safe : SPAIColor.accent).opacity(0.18),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                (tour.justSatisfied ? SPAIColor.safe : SPAIColor.accent).opacity(0.5),
                lineWidth: 1
            )
        )
        .scaleEffect(tour.justSatisfied ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: tour.justSatisfied)
    }

    // MARK: - Finished

    private var finishedCard: some View {
        card {
            VStack(alignment: .leading, spacing: SPAISpacing.m) {
                header(title: "You're set", badge: nil)

                Text("You can replay this any time from Settings. If you get stuck mid-session, ask SPAI from the Chat bubble on your wrist.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    primaryButton("Start working") {
                        appModel.completeTour()
                        tour.finish()
                    }
                }
            }
        }
    }

    // MARK: - Chrome

    private func header(title: String, badge: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: SPAISpacing.m)
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize()
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(tour.steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == tour.stepIndex ? SPAIColor.primary : Color.white.opacity(0.25))
                    .frame(width: index == tour.stepIndex ? 16 : 6, height: 5)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tour.stepIndex)
        .accessibilityHidden(true)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(SPAISpacing.l)
            .frame(width: 420, alignment: .leading)
            .spaiPanelBackground(opacity: 0.92)
            .overlay(
                RoundedRectangle(cornerRadius: SPAIRadius.large)
                    .stroke(SPAIColor.primary.opacity(0.55), lineWidth: 2)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Guided tour")
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, SPAISpacing.l)
                .padding(.vertical, SPAISpacing.s + 2)
                .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .spaiHitTarget(pop: 1.10)
        .accessibilityLabel(title)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, SPAISpacing.m)
                .padding(.vertical, SPAISpacing.s)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .spaiHitTarget()
        .accessibilityLabel(title)
    }
}

#Preview("Tour Coachmark") {
    let model = AppModel()
    model.tour.start()
    return TourCoachmark()
        .environment(model)
        .padding(60)
        .background(.black)
}
