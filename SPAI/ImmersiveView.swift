//
//  ImmersiveView.swift
//  SPAI
//
//  Hosts the immersive space content: the RealityKit scene plus the
//  detection overlay floating in 3D world space, with an exit control.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    // Shared app state, so opening/closing keeps immersiveSpaceState accurate.
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    // Hardcoded sample detections for now; later populated from the backend.
    let detections: [Detection] = Detection.sampleDetections

    var body: some View {
        ZStack {
            // Existing RealityKit scene (skybox / starter content).
            RealityView { content in
                if let immersiveContentEntity = try? await Entity(
                    named: "Immersive",
                    in: realityKitContentBundle
                ) {
                    content.add(immersiveContentEntity)
                }
            }

            // Detection overlay layered on top, floating in world space.
            DetectionOverlayView(detections: detections)

            // Exit control pinned to the bottom so the user can always leave.
            VStack {
                Spacer()
                Button {
                    Task {
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Exit Workflow")
                            .fontWeight(.semibold)
                    }
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(SPAIColor.critical)
                    .clipShape(RoundedRectangle(cornerRadius: SPAIRadius.medium))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 60)
            }
        }
        // These two are the real source of truth for whether the space is open.
        // Setting state here (not in the open/close buttons) keeps it accurate
        // no matter how the space was entered or dismissed.
        .onAppear {
            appModel.immersiveSpaceState = .open
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
