//
//  InstrumentCatalog.swift
//  SPAI
//
//  What SPAI knows about each instrument, and the rule for deciding which
//  instrument the user is holding up.
//
//  Mirrors backend/app/instruments.py. The app carries its own copy so it can
//  still name an instrument when it has dropped to on-device detection and
//  the backend is unreachable.
//

import Foundation

// MARK: - Reference card

struct InstrumentInfo: Identifiable, Equatable {
    let key: String
    let name: String
    let category: String
    /// One line: what it is for.
    let summary: String
    /// Short sentence read aloud when the instrument is identified.
    let spoken: String
    /// How to tell it apart from look-alikes.
    let identifyBy: String
    /// Inspection-bench checkpoints.
    let inspect: [String]
    /// Decontamination / assembly handling note.
    let handling: String
    let icon: String

    var id: String { key }
}

enum InstrumentCatalog {
    /// Label reported when something instrument-shaped is seen but not named.
    static let genericLabel = "instrument"

    /// Below this confidence SPAI says "an instrument" instead of guessing a
    /// name. A wrong name is worse than no name for someone learning the set.
    static let identifyThreshold = 0.60

    static let all: [InstrumentInfo] = [
        InstrumentInfo(
            key: "adson_dressing_forceps",
            name: "Adson Dressing Forceps",
            category: "Thumb forceps",
            summary: "Fine-tipped thumb forceps for handling dressings and delicate tissue.",
            spoken: "Adson dressing forceps. Fine-tipped thumb forceps for dressings and delicate tissue.",
            identifyBy: "Tweezer-style with a wide flat grip that narrows to fine, serrated tips. No teeth and no ratchet.",
            inspect: [
                "Tips meet evenly and do not cross",
                "Serrations are clean, no trapped soil",
                "Spring tension returns the tips open"
            ],
            handling: "Protect the fine tips — never stack heavy instruments on top.",
            icon: "pencil.tip"
        ),
        InstrumentInfo(
            key: "babcock_tissue_forceps",
            name: "Babcock Tissue Forceps",
            category: "Grasping forceps",
            summary: "Ratcheted forceps with rounded, open jaws for holding delicate tissue without crushing it.",
            spoken: "Babcock tissue forceps. Rounded open jaws that hold delicate tissue without crushing it.",
            identifyBy: "Ring handles and a ratchet, with broad, flared, window-like jaw tips that have no teeth.",
            inspect: [
                "Jaws meet evenly at the tips",
                "Box lock is clean and moves smoothly",
                "Ratchet holds on every tooth and releases cleanly"
            ],
            handling: "Clean and sterilize unlocked and open so the box lock is exposed.",
            icon: "scissors"
        ),
        InstrumentInfo(
            key: "halsted_mosquito_forceps",
            name: "Halsted Mosquito Forceps",
            category: "Hemostat",
            summary: "Small, fine hemostat for clamping small blood vessels.",
            spoken: "Halsted mosquito forceps. A small, fine hemostat for clamping small vessels.",
            identifyBy: "The smallest ratcheted clamp in the set: ring handles with short, slim jaws serrated along their full length.",
            inspect: [
                "Tips align and close fully with no gap",
                "Ratchet holds on the first tooth",
                "Box lock is free of soil, cracks, and rust"
            ],
            handling: "Open the ratchet before cleaning; string with hinges open for assembly.",
            icon: "scissors"
        ),
        InstrumentInfo(
            key: "mayo_hegar_needle_holder",
            name: "Mayo-Hegar Needle Holder",
            category: "Needle holder",
            summary: "Ratcheted needle holder with short, heavy jaws for driving suture needles.",
            spoken: "Mayo-Hegar needle holder. Short, heavy jaws that grip a suture needle.",
            identifyBy: "Looks like a sturdy hemostat, but the jaws are shorter and thicker with a cross-hatched grip. Gold rings mean tungsten carbide inserts.",
            inspect: [
                "Jaws are not worn smooth — a needle must not rotate",
                "No light shows between closed jaws",
                "Ratchet holds and box lock moves smoothly"
            ],
            handling: "Check the jaw inserts for cracks or lifting before it goes in the tray.",
            icon: "scissors"
        ),
        InstrumentInfo(
            key: "operating_scissors",
            name: "Operating Scissors",
            category: "Scissors",
            summary: "General-purpose scissors for cutting suture, dressings, and drapes.",
            spoken: "Operating scissors. General-purpose scissors for suture and dressings.",
            identifyBy: "Straight or curved blades with ring handles and no ratchet. Tips may be sharp, blunt, or one of each.",
            inspect: [
                "Blades are free of nicks, burrs, and cracks",
                "Blades cut cleanly all the way to the tip",
                "Screw joint is tight and the action is smooth"
            ],
            handling: "Keep blades open during cleaning and protect the tips in the tray.",
            icon: "scissors"
        ),
        InstrumentInfo(
            key: "scalpel_handle_3",
            name: "Scalpel Handle No. 3",
            category: "Scalpel handle",
            summary: "Reusable knife handle that holds small blades — numbers 10, 11, 12, and 15.",
            spoken: "Number 3 scalpel handle. It holds blades 10, 11, 12, and 15.",
            identifyBy: "A flat, slim metal handle with a narrow grooved tip where the blade slides on. No moving parts.",
            inspect: [
                "No blade is still attached",
                "Blade slot is clean, straight, and not bent",
                "Grip grooves are free of soil"
            ],
            handling: "Blades come off with a blade remover before decontamination — never by hand.",
            icon: "pencil.line"
        )
    ]

    private static let byKey: [String: InstrumentInfo] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// Alternate spellings a model or relabelled dataset might produce.
    private static let aliases: [String: String] = [
        "adson_forceps": "adson_dressing_forceps",
        "babcock_forceps": "babcock_tissue_forceps",
        "mosquito_forceps": "halsted_mosquito_forceps",
        "halsted_mosquito": "halsted_mosquito_forceps",
        "needle_holder": "mayo_hegar_needle_holder",
        "mayo_hegar": "mayo_hegar_needle_holder",
        "scissors": "operating_scissors",
        "scalpel_handle": "scalpel_handle_3",
        "scalpel_handle_no_3": "scalpel_handle_3",
        "scalpel": "scalpel_handle_3"
    ]

    /// Collapses a model label to a lookup key: lowercase letters and digits
    /// joined by single underscores. "Mayo-Hegar Needle Holder" and
    /// "mayo hegar needle holder" both become "mayo_hegar_needle_holder".
    static func key(for label: String) -> String {
        var key = ""
        var pendingSeparator = false
        for scalar in label.lowercased().unicodeScalars {
            // ASCII a–z and 0–9 only; everything else is a separator.
            let isAlphanumeric = (97...122).contains(scalar.value) || (48...57).contains(scalar.value)
            if isAlphanumeric {
                if pendingSeparator && !key.isEmpty { key.append("_") }
                key.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else {
                pendingSeparator = true
            }
        }
        return aliases[key] ?? key
    }

    static func lookup(_ label: String) -> InstrumentInfo? {
        byKey[key(for: label)]
    }

    static func displayName(for label: String) -> String {
        if let info = lookup(label) { return info.name }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Instrument" : trimmed
    }
}

// MARK: - Identification result

/// The one instrument SPAI believes the user is showing it.
struct IdentifiedInstrument: Equatable {
    let key: String
    let name: String
    let confidence: Double
    /// A hand or glove is on it — it is being held up, not lying on the bench.
    let held: Bool
    /// False when something instrument-shaped was seen but SPAI won't name it.
    let certain: Bool
    let info: InstrumentInfo?

    var confidencePercent: Int { Int((confidence * 100).rounded()) }

    /// Sentence read aloud and shown in the guide's speech bubble.
    var spoken: String {
        if let info, certain { return info.spoken }
        return "I can see an instrument, but I'm not sure which one. Hold it flat and a little closer."
    }
}

// MARK: - Which instrument is being shown?

enum InstrumentIdentifier {
    /// How far a hand/glove box is grown before testing overlap with an
    /// instrument. Fingers wrap the handle, so boxes usually touch rather
    /// than fully overlap.
    private static let handReach = 0.15

    /// Picks the single instrument the user is most likely showing.
    ///
    /// Preference order: an instrument in someone's hand beats one lying on
    /// the bench; then the more confident detection; then the larger one.
    /// Returns nil when there is no instrument in frame.
    static func identify(
        in detections: [BackendDetection],
        threshold: Double = InstrumentCatalog.identifyThreshold
    ) -> IdentifiedInstrument? {
        let hands = detections.filter { DetectionService.isPPEClass($0.className) }
        let instruments = detections.filter { DetectionService.isInstrumentClass($0.className) }
        guard !instruments.isEmpty else { return nil }

        let reach = hands.compactMap { expanded($0.box, by: handReach) }
        let ranked = instruments.map { detection -> (detection: BackendDetection, held: Bool) in
            let held = detection.held ?? reach.contains { overlaps($0, detection.box) }
            return (detection, held)
        }

        guard let best = ranked.max(by: { isLowerPriority($0, than: $1) }) else { return nil }

        let info = InstrumentCatalog.lookup(best.detection.key ?? best.detection.className)
        let certain = info != nil && best.detection.confidence >= threshold

        return IdentifiedInstrument(
            key: certain ? (info?.key ?? InstrumentCatalog.genericLabel) : InstrumentCatalog.genericLabel,
            name: certain ? (info?.name ?? "Instrument") : "Instrument",
            confidence: best.detection.confidence,
            held: best.held,
            certain: certain,
            info: certain ? info : nil
        )
    }

    private static func isLowerPriority(
        _ a: (detection: BackendDetection, held: Bool),
        than b: (detection: BackendDetection, held: Bool)
    ) -> Bool {
        if a.held != b.held { return !a.held && b.held }
        if a.detection.confidence != b.detection.confidence {
            return a.detection.confidence < b.detection.confidence
        }
        return area(a.detection.box) < area(b.detection.box)
    }

    private static func expanded(_ box: [Int], by factor: Double) -> [Double]? {
        guard box.count == 4 else { return nil }
        let dx = Double(box[2] - box[0]) * factor
        let dy = Double(box[3] - box[1]) * factor
        return [Double(box[0]) - dx, Double(box[1]) - dy, Double(box[2]) + dx, Double(box[3]) + dy]
    }

    private static func overlaps(_ a: [Double], _ b: [Int]) -> Bool {
        guard b.count == 4 else { return false }
        return a[0] < Double(b[2]) && Double(b[0]) < a[2]
            && a[1] < Double(b[3]) && Double(b[1]) < a[3]
    }

    private static func area(_ box: [Int]) -> Int {
        guard box.count == 4 else { return 0 }
        return max(box[2] - box[0], 0) * max(box[3] - box[1], 0)
    }
}

// MARK: - Stability over time

/// Turns a noisy frame-by-frame stream of identifications into something
/// calm enough to speak aloud.
///
/// A single frame is not trusted: the same instrument has to be seen in
/// consecutive frames before it is confirmed, and it is only announced again
/// after it has genuinely left the frame. Without this, a flickering box
/// would make SPAI repeat itself or name two instruments back and forth.
struct InstrumentTracker {
    /// Consecutive frames the same instrument must appear in before it is confirmed.
    var framesToConfirm = 2
    /// Consecutive empty frames before the confirmed instrument is dropped.
    var framesToClear = 2
    /// Never repeat the same announcement more often than this.
    var repeatInterval: TimeInterval = 20

    /// The instrument currently confirmed in frame, if any.
    private(set) var current: IdentifiedInstrument?

    private var candidateKey: String?
    private var candidateStreak = 0
    private var missStreak = 0
    private var lastAnnouncedKey: String?
    private var lastAnnouncedAt: Date = .distantPast

    /// Feeds one frame's result in. Returns an instrument when — and only
    /// when — it should be announced to the user now.
    mutating func ingest(_ candidate: IdentifiedInstrument?, at now: Date = Date()) -> IdentifiedInstrument? {
        guard let candidate else {
            candidateKey = nil
            candidateStreak = 0
            missStreak += 1
            if missStreak >= framesToClear {
                current = nil
                // It left the frame, so showing it again is a fresh question.
                lastAnnouncedKey = nil
            }
            return nil
        }

        missStreak = 0
        if candidate.key == candidateKey {
            candidateStreak += 1
        } else {
            candidateKey = candidate.key
            candidateStreak = 1
        }
        guard candidateStreak >= framesToConfirm else { return nil }

        current = candidate

        let isStale = now.timeIntervalSince(lastAnnouncedAt) >= repeatInterval
        let shouldAnnounce: Bool
        if candidate.certain {
            shouldAnnounce = candidate.key != lastAnnouncedKey || isStale
        } else {
            // "Not sure which one" is only worth saying if we haven't just
            // named something — otherwise a brief dip in confidence would
            // talk over an answer the user already has.
            shouldAnnounce = lastAnnouncedKey == nil || isStale
        }
        guard shouldAnnounce else { return nil }

        lastAnnouncedKey = candidate.key
        lastAnnouncedAt = now
        return candidate
    }

    mutating func reset() {
        current = nil
        candidateKey = nil
        candidateStreak = 0
        missStreak = 0
        lastAnnouncedKey = nil
        lastAnnouncedAt = .distantPast
    }
}
