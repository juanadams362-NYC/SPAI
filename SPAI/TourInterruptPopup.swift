//
//  TourInterruptPopup.swift
//  SPAI
//
//  Soft-interrupt card shown when the user taps a control that isn't part of the
//  current guided-tour step.
//
//  Interaction states
//  ──────────────────
//  First wrong tap     Popup appears near the tapped panel. 3.5 s auto-dismiss.
//  Repeated wrong tap  `interruptSeq` changes → SwiftUI treats it as a brand-new
//                       view (via .id()) and re-runs the appear transition. Timer
//                       resets. User sees it "bounce in" again.
//  Dismiss (×)        `tour.dismissInterrupt()` called. Popup disappears immediately
//                       via the disappear transition. Tour continues from current step.
//  Skip               `tour.skip()` called. Tour ends; popup disappears with it.
//
//  Anchor
//  ──────
//  ImmersiveView positions the underlying RealityKit entity near the arc slot of
//  the panel the user just tapped — 0.15 m closer and 0.25 m above the panel
//  centre. That places the popup between the user and the panel, squarely in the
//  line of sight that landed on the wrong button.

import SwiftUI

struct TourInterruptPopup: View {
    @Environment(AppModel.self) private var appModel
    private var tour: AppTour { appModel.tour }

    var body: some View {
        // Wrap in a Group so the transition applies to the whole card, not just
        // one subview. The .id() forces SwiftUI to create a fresh view whenever
        // interruptSeq changes — that re-triggers the appear animation, which is
        // what gives "repeated wrong tap" the shake-in bounce.
        Group {
            if tour.interruptAnchorID != nil {
                card
                    .id(tour.interruptSeq)
                    .transition(
                        .scale(scale: 0.80)
                        .combined(with: .opacity)
                    )
            }
        }
        .animation(
            .spring(response: 0.30, dampingFraction: 0.62),
            value: tour.interruptAnchorID
        )
        // Re-animate whenever the seq ticks (repeated tap), even if the anchor
        // value didn't change.
        .animation(
            .spring(response: 0.30, dampingFraction: 0.62),
            value: tour.interruptSeq
        )
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            // Header
            HStack(spacing: SPAISpacing.s) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SPAIColor.warning)
                Text("This step first")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                // Dismiss (×)
                Button {
                    tour.dismissInterrupt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .spaiHitTarget(minSize: 32)
                .accessibilityLabel("Dismiss")
            }

            // Reminder of what the tour currently wants
            if let cta = tour.currentStep?.callToAction {
                Text(cta)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            } else if tour.currentStep != nil {
                Text("Follow the tour card nearby.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.60))
            }

            // Escape hatch
            Button {
                appModel.completeTour()
                tour.skip()
            } label: {
                Text("Skip tour")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityLabel("Skip tour")
        }
        .padding(SPAISpacing.m)
        .frame(width: 260)
        .spaiPanelBackground(opacity: 0.95)
        .overlay(
            RoundedRectangle(cornerRadius: SPAIRadius.large)
                .stroke(SPAIColor.warning.opacity(0.60), lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tour interrupt")
    }
}

#Preview("Tour Interrupt Popup") {
    let model = AppModel()
    model.tour.start()
    // Simulate a wrong tap while the tour is on the "Start working" step.
    model.tour.note(.openedChat)
    return TourInterruptPopup()
        .environment(model)
        .padding(60)
        .background(.black)
}
