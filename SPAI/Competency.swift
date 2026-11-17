//
//  Competency.swift
//  SPAI
//
//  Scores a run on the headset, using the same rubric as the backend
//  (backend/app/scoring.py), so a student sees their result the moment they
//  finish — even offline. When the run uploads, the server's score is the
//  one of record; the two agree because the rules are the same.
//

import Foundation

struct CompetencyResult: Equatable {
    enum Verdict: String {
        case competent
        case needsPractice = "needs_practice"
        case incomplete

        var label: String {
            switch self {
            case .competent:     return "Competent"
            case .needsPractice: return "Needs practice"
            case .incomplete:    return "Incomplete"
            }
        }
    }

    struct Deduction: Equatable, Identifiable {
        let reason: String
        let count: Int
        let points: Int
        var id: String { reason }
    }

    let score: Int
    let verdict: Verdict
    let deductions: [Deduction]
    /// Plain-language pointers on what to work on.
    let coaching: [String]
}

enum Competency {
    /// Points lost per event. An institution can change these in the
    /// instructor dashboard; they arrive with the protocol.
    static let defaultRubric: [String: Int] = [
        "contamination_penalty": 20,
        "send_back_penalty": 10,
        "redo_penalty": 5,
        "count_mismatch_penalty": 10,
        "pass_score": 80,
        "max_contaminations_to_pass": 0
    ]

    static func score(
        events: [RunEvent],
        completed: Bool,
        stationsCompleted: Int,
        rubric: [String: Int] = [:]
    ) -> CompetencyResult {
        let rules = defaultRubric.merging(rubric) { _, custom in custom }
        func rule(_ key: String) -> Int { rules[key] ?? 0 }
        func count(_ kind: String) -> Int { events.filter { $0.kind == kind }.count }

        let contaminations = count("contamination")
        let rows: [(reason: String, count: Int, each: Int)] = [
            ("Contamination", contaminations, rule("contamination_penalty")),
            ("Tray sent back", count("send_back"), rule("send_back_penalty")),
            ("Station redone", count("redo"), rule("redo_penalty")),
            ("Count sheet mismatch", count("count_mismatch"), rule("count_mismatch_penalty"))
        ]
        let deductions = rows
            .filter { $0.count > 0 }
            .map { CompetencyResult.Deduction(reason: $0.reason, count: $0.count, points: $0.count * $0.each) }

        let score = max(0, 100 - deductions.reduce(0) { $0 + $1.points })

        let verdict: CompetencyResult.Verdict
        if !completed {
            verdict = .incomplete
        } else if score >= rule("pass_score") && contaminations <= rule("max_contaminations_to_pass") {
            // A contamination is a hard stop however good the rest of the
            // run was: the point of the exercise is that it never happens.
            verdict = .competent
        } else {
            verdict = .needsPractice
        }

        return CompetencyResult(
            score: score,
            verdict: verdict,
            deductions: deductions,
            coaching: coaching(events: events, completed: completed, stationsCompleted: stationsCompleted)
        )
    }

    private static func coaching(events: [RunEvent], completed: Bool, stationsCompleted: Int) -> [String] {
        var notes: [String] = []
        for step in SterileStep.allCases {
            func count(_ kind: String) -> Int {
                events.filter { $0.kind == kind && $0.station == step.backendName }.count
            }
            let contaminations = count("contamination")
            if contaminations > 0 {
                let times = contaminations == 1 ? "once" : "\(contaminations) times"
                notes.append("Bare hand detected \(times) at \(step.title). Check your gloves before handling instruments there.")
            }
            if count("send_back") > 0 {
                notes.append("The tray was sent back from \(step.title). Look at what failed and how to catch it a station earlier.")
            }
            if count("count_mismatch") > 0 {
                notes.append("The count sheet did not match at \(step.title). Count against the sheet before closing the tray.")
            }
            if count("redo") >= 2 {
                notes.append("\(step.title) was restarted \(count("redo")) times. Ask for another demonstration of those steps.")
            }
        }
        if !completed {
            let index = min(max(stationsCompleted, 0), SterileStep.allCases.count - 1)
            notes.append("The run ended before finishing. It stopped at \(SterileStep.allCases[index].title).")
        }
        if notes.isEmpty {
            notes.append("Clean run. Every station completed with no alerts.")
        }
        return notes
    }
}
