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

    // Sign-in
    @State private var picked: Learner?
    @State private var pin = ""
    @State private var pinMessage: String?
    @State private var isChecking = false

    // Pairing
    @State private var serverAddress = UserDefaults.standard.string(forKey: "backendURL") ?? ""
    @State private var pairingCode = ""
    @State private var headsetName = ""
    @State private var pairMessage: String?
    @State private var isPairing = false

    private let client = BackendClient()

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.039, blue: 0.035).ignoresSafeArea()

            HStack(alignment: .top, spacing: SPAISpacing.xl) {
                brandColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if connection == .unpaired {
                        pairColumn
                    } else if let picked {
                        pinColumn(for: picked)
                    } else {
                        signInColumn
                    }
                }
                .frame(width: 380)
            }
            .padding(SPAISpacing.xxl)
        }
        .task { await refresh() }
        // Whoever used the headset last is signed out by the time this
        // screen shows. Every session starts with a fresh sign-in.
        .onAppear {
            appModel.signOut()
            picked = nil
            pin = ""
        }
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
        case .connected:   return SchoolConnection.shared.schoolName ?? "Connected"
        case .unpaired:    return "Not connected to a school"
        case .unreachable: return "Working offline"
        case .outdated:    return "Server needs updating"
        }
    }

    private var connectionDetail: String {
        switch connection {
        case .none:
            return "Looking for your school's SPAI server."
        case .connected:
            return "\(ProtocolStore.shared.name). Assessed runs go to your instructor."
        case .unpaired:
            return "Practice works without a school. To sign students in and send runs to an instructor, connect this headset."
        case .unreachable:
            return "Signed-in students can still work. Runs are saved on this headset and sent when the server is back."
        case .outdated:
            return "The server is an older version without schools and sign-in. Guidance still works."
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
                        personRow(learner.name, detail: learner.cohort, isSelected: false) {
                            picked = learner
                            pin = ""
                            pinMessage = nil
                        }
                    }
                    if roster.isEmpty {
                        Text(connection == .connected
                             ? "No students on the roster yet. An instructor adds them on the dashboard."
                             : "The class roster appears here once this headset can reach your school.")
                            .font(.system(size: 14))
                            .foregroundStyle(HomeStyle.stone)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, SPAISpacing.s)
                    }
                }
            }
            .frame(maxHeight: 260)

            Rectangle().fill(HomeStyle.line).frame(height: 1)

            Button {
                appModel.signInAsGuest()
                Task { await enterWorkspace() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practise as a guest")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HomeStyle.paper)
                    Text("Guided and checked, not scored or sent anywhere")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(HomeStyle.ash)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
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

    // MARK: - PIN

    /// A number pad rather than the system keyboard: big targets, no
    /// keyboard popping up in front of the student, and the digits never
    /// shown on screen.
    private func pinColumn(for learner: Learner) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Button {
                picked = nil
                pin = ""
                pinMessage = nil
            } label: {
                Label("Not you?", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(HomeStyle.stone)
            }
            .buttonStyle(.plain)
            .spaiHitTarget()

            Text(learner.name)
                .font(.system(size: 26, weight: .bold).width(.expanded))
                .foregroundStyle(HomeStyle.paper)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Enter your 4-digit PIN")
                .font(.system(size: 15))
                .foregroundStyle(HomeStyle.stone)

            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? HomeStyle.paper : Color.clear)
                        .overlay { Circle().stroke(HomeStyle.paper.opacity(0.6), lineWidth: 1.5) }
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pin.count) of 4 digits entered")

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"], id: \.self) { key in
                    if key.isEmpty {
                        Color.clear.frame(width: 84, height: 56)
                    } else {
                        Button {
                            press(key, for: learner)
                        } label: {
                            Text(key == "⌫" ? "" : key)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(HomeStyle.paper)
                                .overlay { if key == "⌫" { Image(systemName: "delete.left").font(.system(size: 20)).foregroundStyle(HomeStyle.paper) } }
                                .frame(width: 84, height: 56)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .disabled(isChecking || isOpening)
                        .accessibilityLabel(key == "⌫" ? "Delete" : key)
                    }
                }
            }

            if isChecking {
                ProgressView().controlSize(.small)
            }
            if let pinMessage {
                Text(pinMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func press(_ key: String, for learner: Learner) {
        pinMessage = nil
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
            return
        }
        guard pin.count < 4 else { return }
        pin.append(key)
        if pin.count == 4 {
            Task { await checkPin(for: learner) }
        }
    }

    private func checkPin(for learner: Learner) async {
        isChecking = true
        defer { isChecking = false }
        let entered = pin
        do {
            let result = try await client.verifyPin(learnerID: learner.id, pin: entered)
            if result.ok {
                appModel.signIn(learner, pin: entered, checkedOnline: true)
                await enterWorkspace()
                return
            }
            pin = ""
            switch result.reason {
            case "locked":
                let minutes = max(1, ((result.retryIn ?? 600) + 59) / 60)
                pinMessage = "Too many wrong PINs. Try again in \(minutes) minute\(minutes == 1 ? "" : "s"), or ask your instructor for a new PIN."
            case "unknown":
                pinMessage = "Your name was removed from the roster. Ask your instructor."
                await refresh()
            default:
                let left = result.attemptsLeft ?? 0
                pinMessage = "That PIN isn't right. \(left) more tr\(left == 1 ? "y" : "ies") before it locks."
            }
        } catch BackendError.rateLimited {
            pin = ""
            pinMessage = "Too many PIN attempts on this headset. Wait a few minutes."
        } catch {
            // Offline: let the student work. The PIN travels with the run
            // and is checked when it arrives; a wrong one marks the run as
            // unconfirmed so it can't count toward anyone's competency.
            appModel.signIn(learner, pin: entered, checkedOnline: false)
            await enterWorkspace()
        }
    }

    // MARK: - Pairing

    private var pairColumn: some View {
        VStack(alignment: .leading, spacing: SPAISpacing.m) {
            Text("CONNECT TO YOUR SCHOOL")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(HomeStyle.ash)
            Text("Your SPAI admin opens Headsets on the instructor dashboard and shows a code. Enter it here once; this headset stays connected.")
                .font(.system(size: 14))
                .foregroundStyle(HomeStyle.stone)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Server address", text: $serverAddress)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("Pairing code, e.g. CTNG-FG6Y", text: $pairingCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
            TextField("Name for this headset, e.g. Lab headset 2", text: $headsetName)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await pair() }
            } label: {
                HStack(spacing: 10) {
                    if isPairing { ProgressView().controlSize(.small) }
                    Text(isPairing ? "CONNECTING…" : "CONNECT")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                }
                .foregroundStyle(HomeStyle.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(HomeStyle.paper, in: Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .disabled(isPairing || pairingCode.isEmpty || serverAddress.isEmpty)

            if let pairMessage {
                Text(pairMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(SPAIColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(HomeStyle.line).frame(height: 1)

            Button {
                appModel.signInAsGuest()
                Task { await enterWorkspace() }
            } label: {
                Text("Practise without a school")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomeStyle.paper)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
        .padding(SPAISpacing.l)
        .background(HomeStyle.ink2, in: RoundedRectangle(cornerRadius: SPAIRadius.medium))
        .overlay { RoundedRectangle(cornerRadius: SPAIRadius.medium).stroke(HomeStyle.line, lineWidth: 1) }
    }

    private func pair() async {
        isPairing = true
        pairMessage = nil
        defer { isPairing = false }
        var address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        let name = headsetName.trimmingCharacters(in: .whitespaces).isEmpty ? UIDevice.current.name : headsetName
        do {
            let result = try await client.pair(server: address, code: pairingCode, headsetName: name)
            SchoolConnection.shared.savePairing(server: address, token: result.token,
                                                school: result.organization.name, headset: result.device.name)
            pairingCode = ""
            await refresh()
        } catch BackendError.badCode {
            pairMessage = "That code isn't valid. Codes last ten minutes and work once; ask for a new one."
        } catch BackendError.badAddress {
            pairMessage = "That server address doesn't look right. It's shown next to the code on the dashboard."
        } catch BackendError.rateLimited {
            pairMessage = "Too many tries. Wait a few minutes, then try again."
        } catch {
            pairMessage = "Couldn't reach a SPAI server at that address. Check it and that this headset is online."
        }
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
        if state == .unreachable {
            // Offline: offer the last roster this headset saw, so students
            // can still sign in. Their PINs are checked when runs are sent.
            roster = RosterCache.load()
        }
        guard state == .connected else { return }
        if let learners = try? await client.learners() {
            roster = learners
            RosterCache.save(learners)
            // The person mid-sign-in may have been removed from the roster.
            if let current = picked, !learners.contains(current) {
                picked = nil
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

/// The last roster fetched, so a headset that loses its connection can
/// still list the class. Names and cohorts only.
enum RosterCache {
    private static let key = "cachedRoster"

    static func save(_ learners: [Learner]) {
        if let data = try? JSONEncoder().encode(learners) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [Learner] {
        guard SchoolConnection.shared.isPaired,
              let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Learner].self, from: data)) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
