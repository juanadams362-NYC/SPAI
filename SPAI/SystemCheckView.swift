//
//  SystemCheckView.swift
//  SPAI
//
//  A go / no-go list for the headset, for the five minutes before a class
//  or a demo. Each line says what's wrong and the one thing to do about it.
//

import AVFoundation
import Speech
import SwiftUI

struct SystemCheckView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(DetectionService.self) private var detectionService

    struct Check: Identifiable {
        enum Level { case pass, warn, fail }
        let id = UUID()
        let title: String
        let level: Level
        let detail: String
    }

    @State private var checks: [Check] = []
    @State private var isRunning = false

    private let client = BackendClient()

    var body: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s + 2) {
            Button {
                Task { await run() }
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checklist")
                    }
                    Text(checks.isEmpty ? "Run system check" : "Check again")
                }
            }
            .buttonStyle(.spai(.tinted(SPAIColor.primary)))
            .disabled(isRunning)

            if !checks.isEmpty {
                Text(summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(checks.contains { $0.level == .fail } ? SPAIColor.critical
                                     : checks.contains { $0.level == .warn } ? SPAIColor.warning : SPAIColor.safe)
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(check.level))
                            .foregroundStyle(color(check.level))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 20)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(check.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var summary: String {
        let fails = checks.filter { $0.level == .fail }.count
        let warns = checks.filter { $0.level == .warn }.count
        if fails > 0 { return "\(fails) thing\(fails == 1 ? "" : "s") to fix before students start" }
        if warns > 0 { return "Ready, with \(warns) thing\(warns == 1 ? "" : "s") to know" }
        return "Ready"
    }

    private func icon(_ level: Check.Level) -> String {
        switch level {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }

    private func color(_ level: Check.Level) -> Color {
        switch level {
        case .pass: return SPAIColor.safe
        case .warn: return SPAIColor.warning
        case .fail: return SPAIColor.critical
        }
    }

    // MARK: - The checks

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        var results: [Check] = []

        // 1. School and server.
        let connection = await client.connection()
        switch connection {
        case .connected:
            results.append(Check(title: "Connected to \(SchoolConnection.shared.schoolName ?? "your school")", level: .pass,
                                 detail: "Students can sign in and their runs go to the instructor."))
        case .unpaired:
            results.append(Check(title: "Not connected to a school", level: .fail,
                                 detail: "Only guest practice works. Connect from the home screen with a code from the dashboard's Headsets page."))
        case .unreachable:
            results.append(Check(title: "Server not reachable", level: .fail,
                                 detail: "Check Wi-Fi. Students can still sign in from the saved roster; runs send later. Ask SPAI won't work."))
        case .outdated:
            results.append(Check(title: "Server is out of date", level: .fail,
                                 detail: "Update the SPAI server before the session."))
        }

        // 2. Roster.
        if connection == .connected {
            let count = (try? await client.learners().count) ?? 0
            results.append(count > 0
                ? Check(title: "\(count) learner\(count == 1 ? "" : "s") on the roster", level: .pass, detail: "Each signs in with their PIN.")
                : Check(title: "Roster is empty", level: .warn, detail: "Add students on the dashboard, or demo with guest practice."))
        }

        // 3. Protocol.
        await ProtocolStore.shared.refresh(using: client)
        if let current = ProtocolStore.shared.current {
            results.append(Check(title: "Protocol loaded", level: .pass, detail: "\(current.name), version \(current.version)."))
        } else {
            results.append(Check(title: "Using the built-in protocol", level: .warn,
                                 detail: "The school's own wording hasn't been downloaded yet. Fine for a demo."))
        }

        // 4. On-headset checks.
        results.append(detectionService.canRunOnDevice
            ? Check(title: "On-headset detection ready", level: .pass, detail: "Glove and instrument checks run without sending video anywhere.")
            : Check(title: "On-headset detection unavailable", level: .fail,
                    detail: "The Core ML models didn't load. Reinstall the app, or turn off \"Keep camera frames on this headset\" to use the server."))

        // 5. Camera feed.
        if let last = detectionService.lastFrameAt, Date().timeIntervalSince(last) < 15 {
            results.append(Check(title: "Camera feed arriving", level: .pass, detail: "The last frame came in \(Int(Date().timeIntervalSince(last))) s ago."))
        } else {
            results.append(Check(title: "No camera feed right now", level: .warn,
                                 detail: "Start the iPhone camera or load test media in the workspace. Steps can still be confirmed by hand."))
        }

        // 6. Voice.
        let mic = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .granted && speech == .authorized {
            results.append(Check(title: "Voice commands ready", level: .pass, detail: "\"Next\", \"repeat\", \"why\" and \"what is this\" will work."))
        } else if mic == .denied || speech == .denied || speech == .restricted {
            results.append(Check(title: "Microphone or speech recognition is off", level: .warn,
                                 detail: "Turn both on for SPAI in the headset's Settings → Privacy. Buttons still work."))
        } else {
            results.append(Check(title: "Voice not set up yet", level: .warn,
                                 detail: "The headset asks for microphone access at the first step. Say yes."))
        }

        // 7. Runs waiting to send.
        let pending = appModel.pendingUploads.count
        if pending > 0 {
            results.append(Check(title: "\(pending) run\(pending == 1 ? "" : "s") waiting to send", level: .warn,
                                 detail: "They send automatically once the server is reachable."))
            await appModel.flushUploads()
        }

        checks = results
    }
}
