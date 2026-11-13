//
//  HomeView.swift
//  SPAI
//

import SwiftUI

/// The first screen: who is working, what kind of run it is, and whether
/// SPAI is connected. One decision per row, one button to begin.
///
/// A shared classroom headset is picked up by a different student every
/// session, so signing in is the first thing asked and takes one tap.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var roster: [Learner] = []
    @State private var connection: BackendConnection?
    @State private var isOpening = false
    @State private var openError: String?

    private let client = BackendClient()

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.039, blue: 0.035).ignoresSafeArea()

            HStack(alignment: .top, spacing: SPAISpacing.xl) {
                brandColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                signInColumn
                    .frame(width: 360)
            }
            .padding(SPAISpacing.xxl)
        }
        .task { await refresh() }
    }

    // MARK: - Left: brand and status

    private var brandColumn: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.l) {
            Text("SPAI")
                .font(.system(size: 30, weight: .light).width(.expanded))
                .tracking(10)
                .foregroundStyle(HomeStyle.paper)

            VStack(alignment: .leading, spacing: 0) {
                Text("STERILE PROCESSING,")
                    .font(.system(size: 34, weight: .light).width(.expanded))
                Text("SEEN THROUGH AI.")
                    .font(.system(size: 34, weight: .heavy).width(.expanded))
            }
            .foregroundStyle(HomeStyle.paper)
            .minimumScaleFactor(0.6)
            .lineLimit(1)

            Text("Step-by-step guidance at every station, with your gloves and instruments checked as you work.")
                .font(.system(size: 17))
                .foregroundStyle(HomeStyle.stone)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: SPAISpacing.m)

            connectionRow

            if !appModel.pendingUploads.isEmpty {
                Label("\(appModel.pendingUploads.count) finished run\(appModel.pendingUploads.count == 1 ? "" : "s") waiting to send to your instructor",
                      systemImage: "icloud.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundStyle(HomeStyle.stone)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openWindow(id: "settings")
                appModel.isSettingsWindowOpen = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(HomeStyle.paper)
                    .padding(.horizontal, SPAISpacing.m)
                    .padding(.vertical, SPAISpacing.s + 2)
                    .overlay { Capsule().stroke(HomeStyle.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
        }
    }

    /// Says plainly whether SPAI can reach its server, and if not, which of
    /// the three possible things is wrong.
    private var connectionRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomeStyle.paper)
                Text(connectionDetail)
                    .font(.system(size: 14))
                    .foregroundStyle(HomeStyle.stone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomeStyle.paper)
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityLabel("Check the connection again")
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionColor: Color {
        switch connection {
        case .connected:  return SPAIColor.safe
        case .none:       return HomeStyle.ash
        default:          return SPAIColor.warning
        }
    }

    private var connectionTitle: String {
        switch connection {
        case .none:        return "Checking the connection…"
        case .connected:   return "Connected"
        case .unreachable: return "Working offline"
        case .wrongKey:    return "Site key needed"
        case .outdated:    return "Server needs updating"
        }
    }

    private var connectionDetail: String {
        switch connection {
        case .none:
            return "Looking for your SPAI server."
        case .connected:
            return "\(ProtocolStore.shared.name). Runs are sent to your instructor."
        case .unreachable:
            return "Guidance and on-headset checks still work. Runs are saved here and sent when the server is back. Check the address in Settings."
        case .wrongKey:
            return "The server is there but didn't accept this headset. Enter your site's key in Settings."
        case .outdated:
            return "The server is running an older version without class records. Guidance still works."
        }
    }

    // MARK: - Right: sign in and start

    private var signInColumn: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("WHO'S WORKING?")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(HomeStyle.ash)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(roster) { learner in
                        personRow(learner.name, detail: learner.cohort, isSelected: appModel.learner == learner) {
                            appModel.learner = learner
                        }
                    }
                    personRow("Guest", detail: roster.isEmpty ? "No class roster on this server yet" : "Not on the roster",
                              isSelected: appModel.learner == nil) {
                        appModel.learner = nil
                    }
                }
            }
            .frame(maxHeight: 210)

            if appModel.learner == nil {
                TextField("Your name (optional)", text: Binding(
                    get: { appModel.guestName },
                    set: { appModel.guestName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Guest name")
            }

            Picker("Run type", selection: Binding(
                get: { appModel.runMode },
                set: { appModel.runMode = $0 }
            )) {
                ForEach(RunMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(appModel.runMode.detail)
                .font(.system(size: 13))
                .foregroundStyle(HomeStyle.stone)

            Picker("Role", selection: Binding(
                get: { appModel.role },
                set: { appModel.role = $0 }
            )) {
                Text("Trainee").tag(TechRole.trainee)
                Text("Technician").tag(TechRole.technician)
                Text("Instructor").tag(TechRole.supervisor)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Trainees also see the reason behind each step")

            Button {
                Task { await enterWorkspace() }
            } label: {
                HStack(spacing: 10) {
                    if isOpening {
                        ProgressView().controlSize(.small)
                    }
                    Text(isOpening ? "OPENING…" : "ENTER THE WORKSPACE")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                }
                .foregroundStyle(HomeStyle.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(HomeStyle.paper, in: Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .disabled(isOpening)

            if let openError {
                Text(openError)
                    .font(.system(size: 13))
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SPAISpacing.l)
        .background(HomeStyle.ink2, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .overlay { RoundedRectangle(cornerRadius: SPAIRadius.medium).stroke(HomeStyle.line, lineWidth: 1) }
    }

    private func personRow(_ name: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? HomeStyle.paper : HomeStyle.ash)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HomeStyle.paper)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(HomeStyle.ash)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: SPAIRadius.small))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Actions

    /// Checks the server, loads the roster and the school's protocol, and
    /// sends any runs that were finished offline. Every part is allowed to
    /// fail; the app works without a server.
    private func refresh() async {
        connection = nil
        let state = await client.connection()
        connection = state
        guard state == .connected else { return }
        if let learners = try? await client.learners() {
            roster = learners
            // The signed-in learner may have been removed from the roster.
            if let current = appModel.learner, !learners.contains(current) {
                appModel.learner = nil
            }
        }
        await ProtocolStore.shared.refresh(using: client)
        await appModel.flushUploads()
    }

    private func enterWorkspace() async {
        guard appModel.immersiveSpaceState == .closed, !isOpening else { return }
        isOpening = true
        openError = nil
        defer { isOpening = false }

        // Every entry is a fresh run for whoever just signed in.
        appModel.resetWorkflow()
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            appModel.immersiveSpaceState = .open
            dismissWindow(id: "home")
        case .userCancelled:
            appModel.immersiveSpaceState = .closed
        case .error:
            appModel.immersiveSpaceState = .closed
            openError = "The workspace couldn't open. Close other immersive apps and try again."
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}

/// The marketing site's ink-and-paper palette, so the app a school opens
/// looks like the product it was shown.
enum HomeStyle {
    static let ink = Color(red: 0.043, green: 0.039, blue: 0.035)
    static let ink2 = Color(red: 0.082, green: 0.075, blue: 0.063)
    static let paper = Color(red: 0.949, green: 0.937, blue: 0.914)
    static let stone = Color(red: 0.741, green: 0.718, blue: 0.678)
    static let ash = Color(red: 0.541, green: 0.518, blue: 0.482)
    static let line = Color(red: 0.949, green: 0.937, blue: 0.914).opacity(0.22)
}

#Preview {
    HomeView()
        .environment(AppModel())
}
