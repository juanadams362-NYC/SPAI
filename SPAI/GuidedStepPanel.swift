//
//  GuidedStepPanel.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//


//
//  GuidedStepPanel.swift
//  SPAI
//
//  The guided sim: walks the user through the current station's steps
//  one at a time. Detection-verifiable steps gate on live detection
//  state; manual steps take a confirm tap. Visible only while a
//  station step is in progress.
//

import SwiftUI

struct GuidedStepPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService

    private var script: [GuidedStep] { StationScripts.script(for: appModel.currentStep) }

    private var guidedIndex: Int {
        min(appModel.guidedStepIndex, script.count - 1)
    }

    private var step: GuidedStep { script[guidedIndex] }
    private var isLast: Bool { guidedIndex == script.count - 1 }

    /// Live check: does the current detection state satisfy this step?
    private var satisfied: Bool {
        let names = detectionService.detections.map { $0.className.lowercased() }
        switch step.condition {
        case .glovesOn:
            // Gloved hands often fire both classes... glove present is the pass.
            return names.contains("glove")
        case .instrumentsPresent:
            return names.contains("instrument")
        case .trayLoaded:
            return detectionService.trayState == "loaded"
        case .manual:
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            HStack {
                Text("GUIDED · \(appModel.currentStep.title.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("Step \(guidedIndex + 1) of \(script.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SPAIColor.accent)
            }

            Text(step.instruction)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SPAISpacing.s) {
                Image(systemName: verificationIcon)
                    .foregroundStyle(satisfied ? SPAIColor.safe : SPAIColor.warning)
                Text(verificationText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    if isLast {
                        appModel.completeStep()
                    } else {
                        appModel.guidedStepIndex += 1
                    }
                } label: {
                    Label(isLast ? "Finish Station" : "Next Step",
                          systemImage: isLast ? "checkmark.seal" : "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, SPAISpacing.m)
                        .padding(.vertical, SPAISpacing.s)
                        .background(satisfied ? SPAIColor.primary : SPAIColor.neutralMid.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
                .disabled(!satisfied)
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 380)
        .spaiPanelBackground(opacity: appModel.panelOpacity)
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .animation(.easeInOut(duration: 0.25), value: appModel.guidedStepIndex)
    }

    private var verificationIcon: String {
        if step.condition == .manual { return "hand.tap.fill" }
        return satisfied ? "checkmark.circle.fill" : "viewfinder.circle"
    }

    private var verificationText: String {
        if step.condition == .manual { return "Confirm when done" }
        return satisfied ? "Verified by detection" : "Waiting for detection…"
    }
}

#Preview {
    GuidedStepPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
