//
//  StationScripts.swift
//  SPAI
//
//  Created by AVP Student on 7/14/26.
//

import Foundation
import SwiftUI

/// What SPAI checks before a guided step may advance.
enum StepCondition: String {
    case glovesOn = "gloves_on"
    case instrumentsPresent = "instruments_present"
    case trayLoaded = "tray_loaded"
    /// Every instrument on the count sheet is in view, and nothing extra.
    case countMatches = "count_matches"
    case manual
}

struct GuidedStep: Identifiable {
    let id = UUID()
    let instruction: String
    let condition: StepCondition
    /// The reason behind the step. Shown to trainees, who are learning why
    /// as well as what.
    var why: String = ""
}

enum StationScripts {
    /// The steps for a station: the institution's own protocol if the
    /// backend has one, otherwise the standard script built into the app.
    static func script(for step: SterileStep) -> [GuidedStep] {
        if let custom = ProtocolStore.shared.steps(for: step), !custom.isEmpty {
            return custom
        }
        return standard(for: step)
    }

    /// The standard protocol. Mirrors backend/app/protocol.py, and is what
    /// runs when the headset has never reached a server.
    static func standard(for step: SterileStep) -> [GuidedStep] {
        switch step {
        case .decontamination: return [
            GuidedStep(instruction: "Put on your protective gear: a fluid-resistant mask with eye protection, a gown, and heavy-duty gloves.",
                       condition: .glovesOn,
                       why: "It keeps splashes and germs off you before you touch anything dirty."),
            GuidedStep(instruction: "Keep the instruments wet and take apart any that come apart.",
                       condition: .instrumentsPresent,
                       why: "Dried-on soil is much harder to clean, and hidden surfaces need to be exposed."),
            GuidedStep(instruction: "Scrub gently under the water line with a soft brush. Brush and flush any instrument with a channel inside.",
                       condition: .manual,
                       why: "Scrubbing under water stops soil spraying into the air."),
            GuidedStep(instruction: "Open and unlock any hinged instruments, then load them into the ultrasonic cleaner or washer.",
                       condition: .manual,
                       why: "Open hinges let the machine clean every surface.")
        ]
        case .inspection: return [
            GuidedStep(instruction: "Make sure your gloves are on and your hands are clean before you handle cleaned instruments.",
                       condition: .glovesOn,
                       why: "From here on, everything needs to stay clean."),
            GuidedStep(instruction: "Look over each instrument under good light and magnification for leftover soil, stains, or rust.",
                       condition: .instrumentsPresent,
                       why: "Anything left on an instrument survives sterilization."),
            GuidedStep(instruction: "Test the moving parts: hinges open and close smoothly, ratchets hold, tips line up.",
                       condition: .manual,
                       why: "An instrument that doesn't work is as much a failure as one that isn't clean."),
            GuidedStep(instruction: "Pull anything that fails. Still dirty goes back to decontamination; broken goes to repair.",
                       condition: .manual,
                       why: "A failed instrument must never reach the tray.")
        ]
        case .trayAssembly: return [
            GuidedStep(instruction: "Check the count sheet. Make sure you have the right sheet for the right tray.",
                       condition: .manual,
                       why: "The sheet lists exactly what goes in this tray."),
            GuidedStep(instruction: "Lay the instruments in as the sheet shows: hinges open, tips pointing the same way, not overcrowded.",
                       condition: .trayLoaded,
                       why: "This lets steam reach every surface."),
            GuidedStep(instruction: "Count the instruments and match them to the sheet exactly.",
                       condition: .countMatches,
                       why: "A missing or extra instrument delays a surgery."),
            GuidedStep(instruction: "Add the chemical indicator in the spot hardest for steam to reach, then close the tray.",
                       condition: .manual,
                       why: "It confirms the sterilizer reached the whole tray.")
        ]
        case .packaging: return [
            GuidedStep(instruction: "Pick the right wrap or container for the tray's size and weight.",
                       condition: .manual,
                       why: "The wrong packaging can tear or block steam."),
            GuidedStep(instruction: "Wrap it snugly with no gaps, holes, or thin spots.",
                       condition: .manual,
                       why: "Any opening lets germs back in after sterilizing."),
            GuidedStep(instruction: "Seal it with indicator tape and label it with the contents, date, and your initials.",
                       condition: .manual,
                       why: "Never use clips or staples, which poke holes.")
        ]
        case .sealValidation: return [
            GuidedStep(instruction: "Check the seal all the way around for gaps, wrinkles, or open channels.",
                       condition: .manual,
                       why: "A channel in the seal is a path for germs."),
            GuidedStep(instruction: "Make sure the outside indicator is there and hasn't already changed color.",
                       condition: .manual,
                       why: "A changed indicator means the pack has already been through a cycle."),
            GuidedStep(instruction: "Check that the label is complete and easy to read, then send the tray to be sterilized.",
                       condition: .manual,
                       why: "The label is how the OR knows what it's opening.")
        ]
        }
    }
}

// MARK: - The institution's protocol

/// Holds the protocol served by the backend, so a school teaches its own
/// procedure in its own words without a new app build.
///
/// The last protocol fetched is kept on the headset. A lab with patchy
/// Wi-Fi still gets the school's wording, not a silent fallback to the
/// standard script.
@MainActor
@Observable
final class ProtocolStore {
    static let shared = ProtocolStore()

    private(set) var current: SiteProtocol?
    private let cacheKey = "cachedSiteProtocol"

    private init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(SiteProtocol.self, from: data) {
            current = cached
        }
    }

    /// Fetches the latest protocol. Keeps the cached one on any failure.
    func refresh(using client: BackendClient = BackendClient()) async {
        guard let fetched = try? await client.fetchProtocol(), isUsable(fetched) else { return }
        if fetched != current {
            current = fetched
        }
        if let data = try? JSONEncoder().encode(fetched) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    /// A protocol missing a station or a step would leave a student with
    /// nothing to do, so anything incomplete is ignored.
    private func isUsable(_ candidate: SiteProtocol) -> Bool {
        SterileStep.allCases.allSatisfy { step in
            candidate.stations.contains { $0.key == step.backendName && !$0.steps.isEmpty }
        }
    }

    func steps(for step: SterileStep) -> [GuidedStep]? {
        guard let station = current?.stations.first(where: { $0.key == step.backendName }) else { return nil }
        return station.steps.map {
            GuidedStep(instruction: $0.instruction,
                       condition: StepCondition(rawValue: $0.condition) ?? .manual,
                       why: $0.why ?? "")
        }
    }

    /// The tray's count sheet: the institution's if it has one, otherwise
    /// one of each instrument SPAI can recognise.
    var countSheet: SiteProtocol.CountSheet {
        if let sheet = current?.countSheets.first, !sheet.items.isEmpty { return sheet }
        return SiteProtocol.CountSheet(
            id: "basic_minor_set",
            name: "Basic Minor Set",
            items: InstrumentCatalog.all.map { SiteProtocol.CountItem(key: $0.key, name: $0.name, count: 1) }
        )
    }

    var rubric: [String: Int] { current?.rubric ?? [:] }
    var name: String { current?.name ?? "SPAI standard protocol" }
}

// MARK: - Count sheet

/// Compares what the camera sees in the tray against the count sheet.
struct CountSheetCheck: Equatable {
    struct Row: Equatable, Identifiable {
        let key: String
        let name: String
        let expected: Int
        let seen: Int
        var id: String { key }
        var isMatched: Bool { seen == expected }
        var isMissing: Bool { seen < expected }
    }

    let rows: [Row]
    /// Instruments in the tray that the sheet doesn't list at all.
    let unexpected: [String]

    /// True only when every listed instrument is present in the right
    /// number and nothing unlisted is in the tray.
    var matches: Bool { rows.allSatisfy(\.isMatched) && unexpected.isEmpty }

    /// One line for the event log and the instructor's report.
    var summary: String {
        var parts: [String] = []
        let missing = rows.filter(\.isMissing).map { "\($0.name) missing" }
        let extra = rows.filter { $0.seen > $0.expected }.map { "extra \($0.name)" }
        parts += missing + extra + unexpected.map { "\($0) not on the sheet" }
        return parts.isEmpty ? "Count matches the sheet" : parts.joined(separator: ", ")
    }

    static func check(sheet: SiteProtocol.CountSheet, seen: [String: Int]) -> CountSheetCheck {
        let rows = sheet.items.map {
            Row(key: $0.key, name: $0.name, expected: $0.count, seen: seen[$0.key] ?? 0)
        }
        let listed = Set(sheet.items.map(\.key))
        let unexpected = seen
            .filter { !listed.contains($0.key) && $0.value > 0 && $0.key != InstrumentCatalog.genericLabel }
            .map { InstrumentCatalog.displayName(for: $0.key) }
            .sorted()
        return CountSheetCheck(rows: rows, unexpected: unexpected)
    }
}
