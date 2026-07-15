//
//  SessionRecord.swift
//  SPAI
//
//  Created by AVP Student on 7/15/26.
//

import Foundation

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let passed: Bool
    let contaminationCount: Int
    let durationSeconds: Int
    let events: [String]

    init(id: UUID = UUID(), date: Date = Date(), passed: Bool,
         contaminationCount: Int, durationSeconds: Int, events: [String]) {
        self.id = id
        self.date = date
        self.passed = passed
        self.contaminationCount = contaminationCount
        self.durationSeconds = durationSeconds
        self.events = events
    }

    var durationText: String {
        String(format: "%02d:%02d", durationSeconds / 60, durationSeconds % 60)
    }

    var dateText: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
@Observable
final class SessionHistory {
    private let key = "sessionHistory"
    private(set) var records: [SessionRecord] = []

    init() { load() }

    func add(_ record: SessionRecord) {
        records.insert(record, at: 0)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
