//
//  GuideCompanion.swift
//  SPAI
//
//  Pip — a small glowing companion that lives in the workspace and shows the
//  user where to look.
//
//  The old tour dimmed the whole view and drew a spotlight at hard-coded
//  screen coordinates, which rarely lined up with where the panels really
//  were. Pip works in the room instead: it reads each panel's actual
//  position, hops over, lands on its top edge, and the panel lights up
//  underneath it. "Look at the detection panel" becomes something you watch
//  happen rather than something you have to go and find.
//
//  Pip is also the app's voice outside the tour: it jumps to the detection
//  panel when contamination is flagged, and names an instrument when you
//  hold one up.
//

import RealityKit
import simd
import SwiftUI
import UIKit

// MARK: - What Pip is saying

struct GuideMessage: Equatable {
    enum Kind: Equatable {
        /// One stop on the tour, with Back / Next controls.
        case tour(step: Int, of: Int)
        /// A passing remark. Dismisses itself.
        case hint
        /// Something needs the user's attention now.
        case alert
        /// An instrument was identified.
        case instrument(confidencePercent: Int)
    }

    var title: String
    var text: String
    var kind: Kind
    var icon: String = "sparkles"
    /// Optional bullet points under the text (inspection checks).
    var points: [String] = []
}

/// One stop on the in-room tour.
struct TourStop {
    /// The panel Pip lands on, or nil to hover in front of the user.
    let panel: String?
    let title: String
    let text: String
}

// MARK: - Pip

@MainActor
@Observable
final class GuideCompanion {
    enum Mood {
        case calm, happy, alert
    }

    static let name = "Pip"

    /// Short on purpose: six stops, one sentence or two each. The feedback on
    /// the old tour was that it was a lot to take in.
    static let tour: [TourStop] = [
        TourStop(
            panel: nil,
            title: "Hi, I'm Pip",
            text: "I'll show you around. It takes about thirty seconds — just follow me."
        ),
        TourStop(
            panel: PanelID.workflow,
            title: "Your five stations",
            text: "This is where you are in the workflow. Press Start Step and I'll walk you through that station."
        ),
        TourStop(
            panel: PanelID.detection,
            title: "I watch your hands here",
            text: "Green means gloves are on. Hold up an instrument and I'll tell you what it is."
        ),
        TourStop(
            panel: PanelID.statusBar,
            title: "Everything else is tucked away",
            text: "Event log, history, and Ask SPAI live under Panels up here. They stay closed until you want them."
        ),
        TourStop(
            panel: nil,
            title: "Check your wrists",
            text: "Turn your left wrist toward you like a watch for stations. Your right wrist has quick actions."
        ),
        TourStop(
            panel: PanelID.workflow,
            title: "That's it",
            text: "I'll hop over to whatever needs your attention. Press Start Step when you're ready."
        )
    ]

    // MARK: Observable state

    /// What the speech bubble is showing. Nil hides the bubble.
    private(set) var message: GuideMessage?
    private(set) var mood: Mood = .calm
    /// Index into `tour` while the tour is running.
    private(set) var tourIndex: Int?

    var isTourRunning: Bool { tourIndex != nil }

    // MARK: Scene graph

    /// Moves around the room. Add this to the RealityView content.
    let root = Entity()
    /// Child of `root` that carries the idle bob, so bobbing and travelling
    /// animate different transforms and never fight.
    private let bobNode = Entity()
    /// Child of `bobNode` that always turns to face the user.
    private let face = Entity()
    @ObservationIgnored private var body: ModelEntity?
    @ObservationIgnored private var ears: [ModelEntity] = []
    @ObservationIgnored private var eyes: [ModelEntity] = []

    @ObservationIgnored private var panels: [String: Entity] = [:]
    @ObservationIgnored private weak var bubble: Entity?
    @ObservationIgnored private weak var appModel: AppModel?

    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var travelTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var spotlightTask: Task<Void, Never>?

    /// Where Pip currently is, or is headed.
    @ObservationIgnored private(set) var perchedPanel: String?

    private static let bodyRadius: Float = 0.032
    /// Where Pip hovers when it isn't on a panel: in front of the user,
    /// a little below eye level.
    private static let hoverPoint = SIMD3<Float>(0, 1.3, -0.85)

    init() {
        buildBody()
    }

    // MARK: Setup

    /// Connects Pip to the room. Call once the panels have been placed.
    /// - Parameters:
    ///   - panels: Every panel Pip may be asked to land on, by `PanelID`.
    ///   - bubble: The speech-bubble attachment's entity.
    func attach(panels: [String: Entity], bubble: Entity?, appModel: AppModel) {
        self.panels = panels
        self.bubble = bubble
        self.appModel = appModel
        root.spatialAudio = SpatialAudioComponent()
        root.position = Self.hoverPoint
        bubble?.position = bubblePoint(for: Self.hoverPoint)
        startIdle()
    }

    func detach() {
        idleTask?.cancel()
        travelTask?.cancel()
        dismissTask?.cancel()
        spotlightTask?.cancel()
        idleTask = nil
        travelTask = nil
        dismissTask = nil
        spotlightTask = nil
        if isTourRunning { endTour(completed: false) }
    }

    // MARK: Going places

    /// Hops onto a panel's top edge.
    func perch(on panelID: String) {
        guard let panel = panels[panelID] else { return }
        perchedPanel = panelID
        travel(to: perchPoint(on: panel))
    }

    /// Floats in front of the user, not on any panel.
    func hover() {
        perchedPanel = nil
        travel(to: Self.hoverPoint)
    }

    /// Lights up a panel's border for a moment without starting the tour.
    func spotlight(_ panelID: String?, for seconds: TimeInterval = 4) {
        spotlightTask?.cancel()
        appModel?.spotlightPanel = panelID
        guard panelID != nil else { return }
        spotlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isTourRunning else { return }
            self.appModel?.spotlightPanel = nil
        }
    }

    // MARK: Saying things

    /// Shows a speech bubble. Pass `duration: nil` to keep it up until
    /// something replaces or dismisses it.
    func say(_ message: GuideMessage, duration: TimeInterval? = 6) {
        // The tour owns the bubble while it runs, except for alerts.
        if isTourRunning, message.kind != .alert, !isTourKind(message.kind) { return }

        dismissTask?.cancel()
        self.message = message
        guard let duration else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            // Don't clear a newer message that replaced this one.
            if self.message == message { self.message = nil }
        }
    }

    /// The user closed the bubble.
    func dismissMessage() {
        dismissTask?.cancel()
        if isTourRunning {
            endTour(completed: false)
        } else {
            message = nil
        }
    }

    /// Clears a passing remark or alert. Leaves the tour alone.
    func clearMessage() {
        guard !isTourRunning else { return }
        dismissTask?.cancel()
        message = nil
    }

    func setMood(_ newMood: Mood) {
        guard newMood != mood else { return }
        mood = newMood
        let material = Self.material(for: newMood)
        body?.model?.materials = [material]
        ears.forEach { $0.model?.materials = [material] }
    }

    /// A quick double hop on the spot.
    func celebrate() {
        setMood(.happy)
        let home = root.position
        travelTask?.cancel()
        travelTask = Task { [weak self] in
            for _ in 0..<2 {
                guard let self, !Task.isCancelled else { return }
                self.root.move(to: Transform(translation: home + [0, 0.06, 0]),
                               relativeTo: self.root.parent, duration: 0.18, timingFunction: .easeOut)
                try? await Task.sleep(for: .seconds(0.18))
                guard !Task.isCancelled else { return }
                self.root.move(to: Transform(translation: home),
                               relativeTo: self.root.parent, duration: 0.18, timingFunction: .easeIn)
                try? await Task.sleep(for: .seconds(0.2))
            }
        }
    }

    // MARK: Tour

    func startTour() {
        guard let appModel else { return }
        dismissTask?.cancel()
        setMood(.calm)
        appModel.isTourActive = true
        showTourStop(0)
    }

    func advanceTour() {
        guard let index = tourIndex else { return }
        if index + 1 < Self.tour.count {
            showTourStop(index + 1)
        } else {
            endTour(completed: true)
        }
    }

    func backTour() {
        guard let index = tourIndex, index > 0 else { return }
        showTourStop(index - 1)
    }

    func endTour(completed: Bool) {
        tourIndex = nil
        message = nil
        spotlightTask?.cancel()
        appModel?.spotlightPanel = nil
        appModel?.isTourActive = false
        appModel?.hasSeenSpatialTour = true
        SpeechManager.shared.stop()
        if completed { celebrate() }
    }

    private func showTourStop(_ index: Int) {
        let stop = Self.tour[index]
        tourIndex = index

        if let panelID = stop.panel {
            appModel?.spotlightPanel = panelID
            perch(on: panelID)
        } else {
            appModel?.spotlightPanel = nil
            hover()
        }

        message = GuideMessage(
            title: stop.title,
            text: stop.text,
            kind: .tour(step: index + 1, of: Self.tour.count),
            icon: "sparkles"
        )
        // Spoken only if the user has spoken guidance turned on.
        SpeechManager.shared.speak(stop.text, anchor: root)
    }

    private func isTourKind(_ kind: GuideMessage.Kind) -> Bool {
        if case .tour = kind { return true }
        return false
    }

    // MARK: Movement

    /// Travels to a point in a single arcing hop, then settles.
    private func travel(to target: SIMD3<Float>) {
        travelTask?.cancel()
        let start = root.position
        let distance = simd_distance(start, target)

        // The bubble glides alongside rather than hopping.
        let bubbleTarget = bubblePoint(for: target)

        guard distance > 0.01 else {
            bubble?.position = bubbleTarget
            return
        }

        // Longer trips take longer, within reason, and arc higher.
        let duration = Double(min(max(distance * 0.75, 0.5), 1.1))
        let apex = (start + target) / 2 + SIMD3<Float>(0, min(0.07 + distance * 0.16, 0.24), 0)

        bubble?.move(to: Transform(translation: bubbleTarget),
                     relativeTo: bubble?.parent, duration: duration, timingFunction: .easeInOut)

        travelTask = Task { [weak self] in
            guard let self else { return }
            self.root.move(to: Transform(translation: apex),
                           relativeTo: self.root.parent, duration: duration / 2, timingFunction: .easeOut)
            try? await Task.sleep(for: .seconds(duration / 2))
            guard !Task.isCancelled else { return }

            self.root.move(to: Transform(translation: target),
                           relativeTo: self.root.parent, duration: duration / 2, timingFunction: .easeIn)
            try? await Task.sleep(for: .seconds(duration / 2))
            guard !Task.isCancelled else { return }

            // Squash on landing. The idle bob restores the shape on its next beat.
            self.bobNode.move(to: Transform(scale: [1.2, 0.76, 1.2]),
                              relativeTo: self.root, duration: 0.09, timingFunction: .easeOut)
            try? await Task.sleep(for: .seconds(0.09))
            guard !Task.isCancelled else { return }
            self.bobNode.move(to: Transform(scale: .one),
                              relativeTo: self.root, duration: 0.16, timingFunction: .easeOut)
        }
    }

    /// The spot on a panel's top edge where Pip lands: toward the viewer's
    /// left, so it sits beside the panel's title rather than over it.
    private func perchPoint(on panel: Entity) -> SIMD3<Float> {
        let center = panel.position
        let halfSize = panelHalfSize(panel)
        let (outward, viewerRight) = viewAxes(at: center)

        return center
            + SIMD3<Float>(0, halfSize.y + Self.bodyRadius * 0.8, 0)
            - viewerRight * (halfSize.x * 0.55)
            // Nudged toward the user so it reads as sitting on the panel's
            // front edge, not floating behind it.
            - outward * 0.02
    }

    /// Half the panel's width and height in metres.
    private func panelHalfSize(_ panel: Entity) -> SIMD2<Float> {
        let extents = panel.visualBounds(relativeTo: panel).extents
        let width = extents.x, height = extents.y
        // Bounds are empty until the attachment has laid out; fall back to a
        // typical panel size rather than landing somewhere wild.
        guard width.isFinite, height.isFinite, (0.03...3).contains(width), (0.02...3).contains(height) else {
            return SIMD2<Float>(0.13, 0.07)
        }
        return SIMD2<Float>(width / 2, height / 2)
    }

    /// Where the speech bubble goes for a given Pip position: above Pip, or —
    /// when Pip is already high up — below and in front, so the bubble never
    /// ends up over the user's head.
    private func bubblePoint(for point: SIMD3<Float>) -> SIMD3<Float> {
        let (outward, viewerRight) = viewAxes(at: point)
        if point.y > 1.6 {
            return point + SIMD3<Float>(0, -0.2, 0) - outward * 0.12 + viewerRight * 0.1
        }
        return point + SIMD3<Float>(0, 0.16, 0) - outward * 0.05
    }

    /// Horizontal directions as seen by a user standing at the origin and
    /// looking at `point`: away from them, and to their right.
    private func viewAxes(at point: SIMD3<Float>) -> (outward: SIMD3<Float>, viewerRight: SIMD3<Float>) {
        var outward = SIMD3<Float>(point.x, 0, point.z)
        let len = simd_length(outward)
        outward = len > 0.01 ? outward / len : SIMD3<Float>(0, 0, -1)
        return (outward, SIMD3<Float>(-outward.z, 0, outward.x))
    }

    // MARK: Idle life

    private func startIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            var rising = true
            var beat = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.bobNode.move(to: Transform(translation: [0, rising ? 0.006 : -0.004, 0]),
                                  relativeTo: self.root, duration: 1.2, timingFunction: .easeInOut)
                rising.toggle()
                beat += 1
                if beat % 3 == 0 { self.blink() }
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    private func blink() {
        for eye in eyes {
            let open = eye.transform
            var closed = open
            closed.scale.y *= 0.12
            eye.move(to: closed, relativeTo: eye.parent, duration: 0.07, timingFunction: .easeIn)
            Task {
                try? await Task.sleep(for: .seconds(0.12))
                eye.move(to: open, relativeTo: eye.parent, duration: 0.09, timingFunction: .easeOut)
            }
        }
    }

    // MARK: Building Pip

    /// Pip is built from primitives at runtime — a glowing body, two ears,
    /// two eyes — so there is no model asset to ship or keep in sync.
    private func buildBody() {
        root.name = "Pip"
        root.addChild(bobNode)
        bobNode.addChild(face)
        face.components.set(BillboardComponent())

        let glow = Self.material(for: .calm)
        let radius = Self.bodyRadius

        let body = ModelEntity(mesh: .generateSphere(radius: radius), materials: [glow])
        face.addChild(body)
        self.body = body

        for side in [-1, 1] as [Float] {
            let ear = ModelEntity(mesh: .generateSphere(radius: radius * 0.34), materials: [glow])
            ear.position = [side * radius * 0.62, radius * 0.82, 0]
            face.addChild(ear)
            ears.append(ear)

            let eye = ModelEntity(
                mesh: .generateSphere(radius: radius * 0.17),
                materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1))]
            )
            eye.position = [side * radius * 0.36, radius * 0.16, radius * 0.9]
            eye.scale = [1, 1.35, 0.5]
            face.addChild(eye)
            eyes.append(eye)

            let glint = ModelEntity(
                mesh: .generateSphere(radius: radius * 0.055),
                materials: [UnlitMaterial(color: .white)]
            )
            glint.position = [radius * 0.05, radius * 0.07, radius * 0.16]
            eye.addChild(glint)
        }
    }

    private static func material(for mood: Mood) -> PhysicallyBasedMaterial {
        let color: UIColor
        switch mood {
        case .calm:  color = UIColor(red: 0.404, green: 0.910, blue: 0.976, alpha: 1)   // #67E8F9
        case .happy: color = UIColor(red: 0.290, green: 0.871, blue: 0.502, alpha: 1)   // #4ADE80
        case .alert: color = UIColor(red: 0.984, green: 0.443, blue: 0.522, alpha: 1)   // #FB7185
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 0.9
        material.roughness = 0.35
        material.metallic = 0.0
        return material
    }
}

// MARK: - Speech bubble

/// Pip's speech bubble. Lives in its own attachment so it can face the user
/// and follow Pip around the room.
struct GuideBubbleView: View {
    let guide: GuideCompanion

    var body: some View {
        // Kept in the hierarchy even when empty so the attachment's entity
        // always exists; ImmersiveView hides the entity when there's nothing
        // to say.
        Group {
            if let message = guide.message {
                bubble(message)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: guide.message)
    }

    private func bubble(_ message: GuideMessage) -> some View {
        VStack(alignment: .leading, spacing: SPAISpacing.s + 2) {
            HStack(spacing: SPAISpacing.s) {
                Image(systemName: message.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SPAIColor.onFill)
                    .frame(width: 28, height: 28)
                    .background(accent(for: message.kind), in: Circle())
                    .shadow(color: accent(for: message.kind).opacity(0.7), radius: 6)
                Text(GuideCompanion.name)
                    .spaiEyebrow(accent(for: message.kind))
                Spacer()
                trailing(for: message.kind)
            }

            Text(message.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(SPAIText.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(message.text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if !message.points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(message.points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(SPAIColor.safe)
                                .padding(.top, 2)
                            Text(point)
                                .font(SPAIFont.callout)
                                .foregroundStyle(SPAIText.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if case .tour(let step, let total) = message.kind {
                tourControls(step: step, total: total)
            }
        }
        .padding(SPAISpacing.m + 2)
        .frame(width: 340, alignment: .leading)
        .spaiPanelBackground(opacity: 0.9, cornerRadius: SPAIRadius.medium)
        .overlay {
            RoundedRectangle(cornerRadius: SPAIRadius.medium, style: .continuous)
                .strokeBorder(accent(for: message.kind).opacity(0.75), lineWidth: 1.5)
        }
        .shadow(color: accent(for: message.kind).opacity(0.35), radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(GuideCompanion.name) says: \(message.title). \(message.text)")
    }

    @ViewBuilder
    private func trailing(for kind: GuideMessage.Kind) -> some View {
        switch kind {
        case .tour(let step, let total):
            Text("\(step) of \(total)")
                .font(SPAIFont.value)
                .foregroundStyle(SPAIText.tertiary)
        case .instrument(let percent):
            SPAIChip(text: "\(percent)% sure", tint: SPAIColor.safe)
        case .hint, .alert:
            Button {
                guide.dismissMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SPAIText.secondary)
            }
            .buttonStyle(.plain)
            .spaiHitTarget()
            .accessibilityLabel("Dismiss")
        }
    }

    private func tourControls(step: Int, total: Int) -> some View {
        HStack(spacing: SPAISpacing.s) {
            Button("Skip") { guide.endTour(completed: false) }
                .buttonStyle(.spai(.ghost, size: .small))
                .accessibilityLabel("Skip the tour")

            Spacer()

            if step > 1 {
                Button("Back") { guide.backTour() }
                    .buttonStyle(.spai(.glass, size: .small))
            }

            Button {
                guide.advanceTour()
            } label: {
                Label(step < total ? "Next" : "Done", systemImage: step < total ? "arrow.right" : "checkmark")
            }
            .buttonStyle(.spai(.primary, size: .small))
        }
        .padding(.top, SPAISpacing.xs)
    }

    private func accent(for kind: GuideMessage.Kind) -> Color {
        switch kind {
        case .alert:      return SPAIColor.critical
        case .instrument: return SPAIColor.safe
        case .tour, .hint: return SPAIColor.primaryBright
        }
    }
}
