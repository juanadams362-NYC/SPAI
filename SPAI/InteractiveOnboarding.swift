//
//  InteractiveOnboarding.swift
//  SPAI
//
//  Interactive guided tour that highlights actual UI elements
//

import SwiftUI

// MARK: - Onboarding Step Model

struct OnboardingStep: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let targetPosition: OnboardingPosition
    let arrow: OnboardingArrow
    let action: (() -> Void)?
    
    init(title: String, message: String, targetPosition: OnboardingPosition, arrow: OnboardingArrow = .top, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.targetPosition = targetPosition
        self.arrow = arrow
        self.action = action
    }
}

enum OnboardingPosition {
    case statusBar
    case detectionPanel
    case eventLog
    case workflowProgress
    case guidedStep
    case simTest
    case settings
    case custom(CGPoint)
}

enum OnboardingArrow {
    case top, bottom, left, right, topLeft, topRight
}

// MARK: - Interactive Onboarding Overlay

struct InteractiveOnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isActive: Bool
    
    @State private var currentStepIndex = 0
    @State private var spotlightFrame: CGRect = .zero
    @State private var viewSize: CGSize = .zero
    
    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to SPAI! 👋",
            message: "Let's take a quick tour of your spatial sterile processing assistant. We'll show you where everything is.",
            targetPosition: .statusBar,
            arrow: .top
        ),
        OnboardingStep(
            title: "Status Bar",
            message: "Your session time, role, and detection mode are always visible here. You can also access Settings and end your session.",
            targetPosition: .statusBar,
            arrow: .top
        ),
        OnboardingStep(
            title: "Detection Panel",
            message: "This shows live PPE compliance, contamination risk, and environment stats. Watch the risk percentage as you work!",
            targetPosition: .detectionPanel,
            arrow: .left
        ),
        OnboardingStep(
            title: "Event Log",
            message: "Every action and alert is logged here in real-time. Perfect for compliance documentation.",
            targetPosition: .eventLog,
            arrow: .right
        ),
        OnboardingStep(
            title: "Workflow Progress",
            message: "Track all 5 sterile processing steps. Tap 'Start Step' to begin with voice guidance and auto-detection.",
            targetPosition: .workflowProgress,
            arrow: .bottom
        ),
        OnboardingStep(
            title: "Testing & Camera",
            message: "Upload test images/videos or connect your iPhone camera via Continuity Camera for live detection testing.",
            targetPosition: .simTest,
            arrow: .bottom
        ),
        OnboardingStep(
            title: "Ready to Go! 🎉",
            message: "You're all set! Start a step to begin the guided workflow, or explore the testing features. Have a great session!",
            targetPosition: .workflowProgress,
            arrow: .bottom
        )
    ]
    
    private var currentStep: OnboardingStep {
        steps[currentStepIndex]
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dim overlay with spotlight cutout
                Color.black.opacity(0.85)
                    .overlay {
                        if spotlightFrame != .zero {
                            Circle()
                                .fill(.clear)
                                .frame(width: spotlightFrame.width + 100, height: spotlightFrame.height + 100)
                                .position(x: spotlightFrame.midX, y: spotlightFrame.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .ignoresSafeArea()
                
                // Tooltip with arrow
                VStack(spacing: 0) {
                    tooltipCard
                        .shadow(color: SPAIColor.primary.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    if currentStep.arrow == .bottom {
                        arrow
                            .rotationEffect(.degrees(180))
                            .offset(y: -1)
                    }
                }
                .position(tooltipPosition(for: geometry.size))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentStepIndex)
            }
            .onAppear {
                viewSize = geometry.size
                updateSpotlight()
            }
            .onChange(of: currentStepIndex) { _, _ in
                updateSpotlight()
                currentStep.action?()
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
                updateSpotlight()
            }
        }
    }
    
    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            HStack {
                Text(currentStep.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(currentStepIndex + 1)/\(steps.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Text(currentStep.message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: SPAISpacing.m) {
                if currentStepIndex > 0 {
                    Button("Back") {
                        withAnimation { currentStepIndex -= 1 }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStepIndex ? SPAIColor.primary : .white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
                
                Button(currentStepIndex < steps.count - 1 ? "Next" : "Start Using SPAI") {
                    if currentStepIndex < steps.count - 1 {
                        withAnimation { currentStepIndex += 1 }
                    } else {
                        completeOnboarding()
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, SPAISpacing.l)
                .padding(.vertical, SPAISpacing.s)
                .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                .buttonStyle(.plain)
            }
        }
        .padding(SPAISpacing.l)
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: SPAIRadius.large)
                .stroke(SPAIColor.primary.opacity(0.5), lineWidth: 2)
        )
    }
    
    private var arrow: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 30))
            .foregroundStyle(Color(white: 0.22))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
    
    private func tooltipPosition(for screenSize: CGSize) -> CGPoint {
        switch currentStep.targetPosition {
        case .statusBar:
            return CGPoint(x: screenSize.width / 2, y: 200)
        case .detectionPanel:
            return CGPoint(x: 250, y: screenSize.height / 2)
        case .eventLog:
            return CGPoint(x: screenSize.width - 250, y: screenSize.height / 2)
        case .workflowProgress:
            return CGPoint(x: screenSize.width / 2, y: screenSize.height - 250)
        case .guidedStep:
            return CGPoint(x: screenSize.width / 2 + 200, y: screenSize.height - 350)
        case .simTest:
            return CGPoint(x: 250, y: screenSize.height - 250)
        case .settings:
            return CGPoint(x: screenSize.width - 200, y: 200)
        case .custom(let point):
            return point
        }
    }
    
    private func updateSpotlight() {
        withAnimation(.easeInOut(duration: 0.3)) {
            spotlightFrame = getSpotlightFrame(for: currentStep.targetPosition, screenSize: viewSize)
        }
    }
    
    private func getSpotlightFrame(for position: OnboardingPosition, screenSize: CGSize) -> CGRect {
        switch position {
        case .statusBar:
            return CGRect(x: screenSize.width / 2 - 550, y: 50, width: 1100, height: 80)
        case .detectionPanel:
            return CGRect(x: 50, y: screenSize.height / 2 - 150, width: 300, height: 300)
        case .eventLog:
            return CGRect(x: screenSize.width - 410, y: screenSize.height / 2 - 150, width: 360, height: 280)
        case .workflowProgress:
            return CGRect(x: screenSize.width / 2 - 380, y: screenSize.height - 180, width: 760, height: 120)
        case .guidedStep:
            return CGRect(x: screenSize.width / 2 - 190, y: screenSize.height - 300, width: 380, height: 200)
        case .simTest:
            return CGRect(x: 50, y: screenSize.height - 280, width: 260, height: 200)
        case .settings:
            return CGRect(x: screenSize.width - 500, y: 50, width: 450, height: 80)
        case .custom(let center):
            return CGRect(x: center.x - 100, y: center.y - 100, width: 200, height: 200)
        }
    }
    
    private func completeOnboarding() {
        withAnimation {
            isActive = false
        }
        appModel.hasCompletedOnboarding = true
    }
}

// MARK: - Onboarding Manager

@MainActor
@Observable
class OnboardingManager {
    var shouldShowInteractive: Bool = false
    
    func startInteractiveTour() {
        shouldShowInteractive = true
    }
    
    func endInteractiveTour() {
        shouldShowInteractive = false
    }
}
