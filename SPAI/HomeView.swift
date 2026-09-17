//
//  HomeView.swift
//  SPAI
//

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(alignment: .leading, spacing: SPAISpacing.xl) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SPAI")
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .tracking(-1.5)

                            Text("Sterile Processing AI\npowered by AI vision.")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        StatusPill(
                            text: "Prototype",
                            systemImage: "sparkles",
                            color: SPAIColor.primary
                        )
                    }

                    HStack(spacing: SPAISpacing.m) {
                        FeatureCard(
                            title: "Guided Workflow",
                            subtitle: "Step-by-step sterile prep support",
                            icon: "checklist.checked"
                        )
                        FeatureCard(
                            title: "AI Detection",
                            subtitle: "PPE, tools, hands, and risk alerts",
                            icon: "viewfinder"
                        )
                        FeatureCard(
                            title: "AR Overlay",
                            subtitle: "Vision Pro-style spatial guidance",
                            icon: "visionpro"
                        )
                    }

                    Spacer()

                    Button {
                        Task {
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
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.fill")
                            Text("Enter Sterile Prep Workflow")
                                .fontWeight(.semibold)
                        }
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                        .background(SPAIColor.primary)
                        .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
                        .shadow(color: SPAIColor.primary.opacity(0.4), radius: 20, y: 8)
                    }
                    .buttonStyle(.plain)
                    .spaiHitTarget()
                    .accessibilityLabel("Enter sterile prep workflow")
                    .accessibilityHint("Opens the spatial workspace and starts a session")
                    .disabled(appModel.immersiveSpaceState != .closed)

                    // Settings was previously reachable only from inside the immersive space,
                    // via the status bar or the wrist menu. That is fine until something in
                    // there stops responding — and then the one screen holding "Replay guided
                    // tour" and the diagnostic logging switch is behind the thing you are
                    // trying to diagnose. Entering the workflow also dismisses this window, so
                    // there was no way back to it either.
                    Button {
                        openWindow(id: "settings")
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, SPAISpacing.l)
                            .padding(.vertical, SPAISpacing.m)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
                    }
                    .buttonStyle(.plain)
                    .spaiHitTarget()
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens settings, where the guided tour can be replayed")
                }
                .padding(SPAISpacing.xxl)
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
}
