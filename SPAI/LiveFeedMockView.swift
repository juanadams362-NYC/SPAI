//
//  LiveFeedMockView.swift
//  SPAI
//
//  Created by AV Student on 4/27/26.
//

import SwiftUI

struct LiveFeedMockView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.11, blue: 0.14),
                            Color(red: 0.02, green: 0.025, blue: 0.035)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            scanGrid

            VStack(spacing: 18) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))

                Text("Live Feed Preview")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Mock camera area for AI overlays and sterile processing guidance")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            overlayContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .overlay {
            RoundedRectangle(cornerRadius: 34)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var scanGrid: some View {
        VStack(spacing: 32) {
            ForEach(0..<8, id: \.self) { _ in
                Rectangle()
                    .fill(.white.opacity(0.035))
                    .frame(height: 1)
            }
        }
        .padding(40)
    }

    private var overlayContent: some View {
        VStack {
            HStack {
                StatusPill(text: "PPE Check Active", systemImage: "dot.radiowaves.left.and.right", color: .green)

                Spacer()

                StatusPill(text: "Demo Mode", systemImage: "cube.transparent", color: .purple)
            }

            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Detection Box")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.9), lineWidth: 3)
                        .frame(width: 230, height: 150)
                        .overlay(alignment: .topLeading) {
                            Text("glove 94%")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .offset(x: 10, y: 10)
                        }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Frame Analysis")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    Text("Safe to continue")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .padding()
                .background(.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(24)
    }
}

#Preview {
    LiveFeedMockView()
        .padding()
        .background(.black)
}
