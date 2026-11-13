//
//  PilotModels.swift
//  SPAI
//
//  The data a class needs: who is working, what protocol they follow, what
//  happened in a run, and how it scored. Matches the backend's pilot routes.
//

import Foundation

// MARK: - Who

struct Learner: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let cohort: String
}

struct RosterResponse: Codable {
    let learners: [Learner]
}

/// Whether a run counts.
enum RunMode: String, Codable, CaseIterable, Identifiable {
    /// Scored and sent to the instructor.
    case assessed
    /// A rehearsal. Still guided and checked, but kept off the record.
    case practice

    var id: String { rawValue }
    var label: String { self == .assessed ? "Assessed run" : "Practice" }
    var detail: String {
        self == .assessed
            ? "Scored and sent to your instructor."
            : "Guided and checked, but not scored against you."
    }
}

// MARK: - Protocol

/// The institution's procedure, as served by the backend (`GET /protocol`).
/// Named SiteProtocol because `Protocol` is a Swift keyword.
struct SiteProtocol: Codable, Equatable {
    struct Step: Codable, Equatable {
        let instruction: String
        let condition: String
        var why: String? = nil
    }

    struct Station: Codable, Equatable {
        let key: String
        let title: String
        let steps: [Step]
    }

    struct CountItem: Codable, Equatable, Identifiable {
        let key: String
        let name: String
        let count: Int
        var id: String { key }
    }

    struct CountSheet: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let items: [CountItem]
    }

    let name: String
    let version: Int
    let stations: [Station]
    var countSheets: [CountSheet] = []
    var rubric: [String: Int] = [:]

    enum CodingKeys: String, CodingKey {
        case name, version, stations, rubric
        case countSheets = "count_sheets"
    }
}

// MARK: - A run

/// One thing that happened, in a form the server can score.
struct RunEvent: Codable, Equatable {
    /// Kinds the rubric understands: station_start, station_complete,
    /// contamination, acknowledge, send_back, redo, count_mismatch.
    /// Anything else is recorded as context.
    let at: String
    let kind: String
    let station: String?
    let message: String
}

/// A whole run, uploaded when it ends (`PUT /sessions/{id}`). Built on the
/// headset so the record survives the network dropping mid-session.
struct RunRecord: Codable, Identifiable, Equatable {
    let id: String
    var learnerID: String?
    var learnerName: String
    var role: String
    var mode: String
    var headset: String
    var startedAt: String
    var endedAt: String
    var durationSeconds: Int
    var completed: Bool
    var stationsCompleted: Int
    var events: [RunEvent]
    var instrumentsSeen: [String]
    var appVersion: String
    var detectionMode: String

    enum CodingKeys: String, CodingKey {
        case id, role, mode, headset, completed, events
        case learnerID = "learner_id"
        case learnerName = "learner_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_s"
        case stationsCompleted = "stations_completed"
        case instrumentsSeen = "instruments_seen"
        case appVersion = "app_version"
        case detectionMode = "detection_mode"
    }
}

/// The server's verdict on an uploaded run. Only the fields the headset shows.
struct ScoredRun: Codable {
    let id: String
    let score: Int
    let verdict: String
    let verdictLabel: String

    enum CodingKeys: String, CodingKey {
        case id, score, verdict
        case verdictLabel = "verdict_label"
    }
}

enum RunClock {
    /// ISO-8601 with a UTC offset, which is what the backend stores.
    static func stamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
