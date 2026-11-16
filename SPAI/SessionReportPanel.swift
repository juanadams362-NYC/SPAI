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
                    VStack(spacing: 6) {
                        ForEach(result.deductions) { deduction in
                            HStack {
                                Text(deduction.count > 1 ? "\(deduction.reason) × \(deduction.count)" : deduction.reason)
                                    .font(SPAIFont.label)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("−\(deduction.points)")
                                    .font(SPAIFont.value)
                                    .foregroundStyle(SPAIColor.warning)
                            }
                        }
                    }
                }

                divider

                VStack(alignment: .leading, spacing: SPAISpacing.s) {
                    Text("WHAT TO WORK ON").spaiEyebrow()
                    ForEach(result.coaching, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(SPAIText.tertiary)
                                .padding(.top, 4)
                            Text(note)
                                .font(SPAIFont.body)
                                .foregroundStyle(.white.opacity(0.92))
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
                        .font(SPAIFont.button)
                        .foregroundStyle(.white)
                        .padding(.horizontal, SPAISpacing.l)
                        .padding(.vertical, SPAISpacing.s + 2)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
                .spaiHitTarget()

                Button {
                    appModel.resetWorkflow()
                } label: {
                    Label("Run Again", systemImage: "arrow.clockwise")
                        .font(SPAIFont.button)
                        .foregroundStyle(.white)
                        .padding(.horizontal, SPAISpacing.l)
                        .padding(.vertical, SPAISpacing.s + 2)
                        .background(SPAIColor.primary, in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                }
                .buttonStyle(.plain)
                .spaiHitTarget()
            }
        }
        .padding(SPAISpacing.l)
        .frame(width: 460)
        .spaiPanel(PanelID.report)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run report for \(appModel.learnerDisplayName). \(result?.verdict.label ?? "No result"). Score \(result?.score ?? 0).")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SPAISpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(appModel.learnerDisplayName.uppercased()) · \(duration)").spaiEyebrow()
                HStack(spacing: 10) {
                    Image(systemName: verdictIcon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(verdictColor)
                    Text(result?.verdict.label ?? "Run complete")
                        .font(.system(size: 28, weight: .bold).width(.expanded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let result {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(result.score)")
                        .font(.system(size: 52, weight: .heavy).width(.expanded))
                        .foregroundStyle(verdictColor)
                    Text("OF 100")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SPAIText.tertiary)
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
        Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
    }
}

#Preview {
    SessionReportPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
