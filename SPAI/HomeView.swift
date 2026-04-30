//
//  HomeView.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SPN AI")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Sterile Processing Navigation powered by AI vision.")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Spacer()

                        StatusPill(text: "Prototype", systemImage: "sparkles", color: .blue)
                    }

                    HStack(spacing: 20) {
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

                    NavigationLink {
                        WorkflowView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                            Text("Start Sterile Prep Scan")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(48)
            }
        }
    }
}

#Preview {
    HomeView()
}
