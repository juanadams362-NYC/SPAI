//
//  SessionReportPanel.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//

import SwiftUI

/// What a student sees the moment a run ends: the result, why, and what to
/// work on. Scored on the headset so it appears instantly; the same run is
/// sent to the instructor, where the server's score is the one of record.
struct SessionReportPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    @State private var celebrate = false

    private var result: CompetencyResult? { appModel.lastResult }

    private var duration: String {
        let seconds = Int(Date().timeIntervalSince(appModel.sessionStart))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var verdictColor: Color {
        switch result?.verdict {
        case .competent:     return SPAIColor.safe
        case .needsPractice: return SPAIColor.warning
        default:             return SPAIText.secondary
        }
    }

    private var verdictIcon: String {
        switch result?.verdict {
        case .competent:     return "checkmark.seal.fill"
        case .needsPractice: return "arrow.triangle.2.circlepath"
        default:             return "circle.dashed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            header
            divider

            if let result {
                if result.deductions.isEmpty {
                    Label("No points lost", systemImage: "checkmark")
                        .font(SPAIFont.label)
                        .foregroundStyle(SPAIColor.safe)
                } else {
                    VStack(spacing: 8) {
                        ForEach(result.deductions) { deduction in
                            HStack {
                                Text(deduction.count > 1 ? "\(deduction.reason) × \(deduction.count)" : deduction.reason)
                                    .font(SPAIFont.label)
                                    .foregroundStyle(SPAIText.primary)
                                Spacer()
                                SPAIChip(text: "−\(deduction.points)", tint: SPAIColor.warning)
                            }
                        }
                    }
                    .padding(12)
                    .background(SPAIColor.surface, in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))
                }

                divider

                VStack(alignment: .leading, spacing: SPAISpacing.s) {
                    Text("What to work on").spaiEyebrow()
                    ForEach(result.coaching, id: \.self) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SPAIColor.primaryBright)
                                .padding(.top, 2)
                            Text(note)
                                .font(SPAIFont.body)
                                .foregroundStyle(SPAIText.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                divider
            }

            HStack(spacing: SPAISpacing.s) {
                Image(systemName: uploadIcon)
                    .foregroundStyle(uploadColor)
                Text(uploadText)
                    .font(SPAIFont.caption)
                    .foregroundStyle(SPAIText.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(uploadColor.opacity(0.1), in: RoundedRectangle(cornerRadius: SPAIRadius.small, style: .continuous))

            HStack(spacing: SPAISpacing.s) {
                Spacer()
                // Hands the headset to the next person: signs out and goes
                // back to the sign-in screen.
                Button {
                    Task {
                        appModel.signOut()
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        openWindow(id: "home")
                    }
                } label: {
                    Label("Next Student", systemImage: "person.2.fill")
                }
                .buttonStyle(.spai(.glass))

                Button {
                    appModel.resetWorkflow()
                } label: {
                    Label("Run Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.spai(.primary))
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 460)
        .spaiPanel(PanelID.report)
        .onAppear { celebrate = true }
        .onChange(of: appModel.sessionComplete) { _, complete in celebrate = complete }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run report for \(appModel.learnerDisplayName). \(result?.verdict.label ?? "No result"). Score \(result?.score ?? 0).")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SPAISpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appModel.learnerDisplayName.uppercased()) · \(duration)").spaiEyebrow()
                HStack(spacing: 12) {
                    Image(systemName: verdictIcon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(verdictColor)
                        .symbolEffect(.bounce, value: celebrate)
                        .frame(width: 50, height: 50)
                        .background {
                            Circle().fill(RadialGradient(colors: [verdictColor.opacity(0.45), verdictColor.opacity(0)],
                                                         center: .center, startRadius: 0, endRadius: 30))
                        }
                        .shadow(color: verdictColor.opacity(0.6), radius: 10)
                    Text(result?.verdict.label ?? "Run complete")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(SPAIText.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let result {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(result.score)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(verdictColor)
                        .shadow(color: verdictColor.opacity(0.45), radius: 12)
                    Text("of 100")
                        .spaiEyebrow(SPAIText.tertiary)
                }
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Where the run went

    private var uploadIcon: String {
        switch appModel.uploadState {
        case .sent:        return "checkmark.icloud.fill"
        case .sending:     return "icloud.and.arrow.up"
        case .waiting:     return "icloud.slash"
        case .notRecorded: return "lock.fill"
        case .needsPairing: return "link.badge.plus"
        case .learnerRemoved: return "person.crop.circle.badge.xmark"
        case .none:        return "icloud"
        }
    }

    private var uploadColor: Color {
        switch appModel.uploadState {
        case .sent:    return SPAIColor.safe
        case .waiting, .needsPairing, .learnerRemoved: return SPAIColor.warning
        default:       return SPAIText.secondary
        }
    }

    private var uploadText: String {
        switch appModel.uploadState {
        case .sent:        return "Sent to your instructor."
        case .sending:     return "Sending to your instructor…"
        case .waiting:     return "Saved on this headset. It will send when the server is reachable."
        case .notRecorded: return appModel.isSignedIn ? "Practice run. Not sent to your instructor." : "Guest practice. Not scored or sent anywhere."
        case .needsPairing: return "Saved on this headset. It will send once the headset is connected to your school again."
        case .learnerRemoved: return "Not recorded: this name is no longer on the class roster."
        case .none:        return ""
        }
    }

    private var divider: some View {
        SPAIDivider()
    }
}

#Preview {
    SessionReportPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
