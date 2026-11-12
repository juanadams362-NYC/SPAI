//
//  BackendClient.swift
//  SPAI
//

import Foundation
import UIKit

// MARK: - Detection models

struct BackendDetection: Codable, Identifiable {
    var id = UUID()
    let classId: Int
    let className: String
    let confidence: Double
    let box: [Int]

    // Instrument detections only — absent on PPE boxes and on responses from
    // older backends, so all three are optional.
    /// Stable catalog id, e.g. "mayo_hegar_needle_holder".
    var key: String? = nil
    /// "instrument" for anything from the instrument model.
    var category: String? = nil
    /// True when the backend saw a hand or glove on this instrument.
    var held: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case classId = "class_id"
        case className = "class_name"
        case confidence
        case box
        case key
        case category
        case held
    }
}

struct DetectResponse: Codable {
    let detections: [BackendDetection]
    let inferenceTimeMs: Int
    let mode: String

    enum CodingKeys: String, CodingKey {
        case detections
        case inferenceTimeMs = "inference_time_ms"
        case mode
    }
}

struct TrayDetectResponse: Codable {
    let detections: [BackendDetection]
    let inferenceTimeMs: Int
    let mode: String
    let instrumentCount: Int
    let trayState: String

    enum CodingKeys: String, CodingKey {
        case detections
        case inferenceTimeMs = "inference_time_ms"
        case mode
        case instrumentCount = "instrument_count"
        case trayState = "tray_state"
    }
}

/// One frame, fully analyzed: PPE boxes, named instruments, and tray state
/// from a single upload (POST /analyze).
struct AnalyzeResponse: Codable {
    let detections: [BackendDetection]
    let instruments: [BackendDetection]
    let instrumentCount: Int
    let trayState: String
    let inferenceTimeMs: Int
    let mode: String

    enum CodingKeys: String, CodingKey {
        case detections
        case instruments
        case instrumentCount = "instrument_count"
        case trayState = "tray_state"
        case inferenceTimeMs = "inference_time_ms"
        case mode
    }
}

// MARK: - Settings models

struct BackendSettings: Codable {
    let confidenceThreshold: Double
    let modelPath: String
    let mode: String

    enum CodingKeys: String, CodingKey {
        case confidenceThreshold = "confidence_threshold"
        case modelPath = "model_path"
        case mode
    }
}

// MARK: - Compliance models

struct ComplianceState: Codable {
    let state: String
    let currentStep: String?
    let eventCount: Int

    enum CodingKeys: String, CodingKey {
        case state
        case currentStep = "current_step"
        case eventCount = "event_count"
    }
}

struct ComplianceEventResult: Codable {
    let accepted: Bool
    let message: String
    let state: String
    let currentStep: String?
    let eventCount: Int

    enum CodingKeys: String, CodingKey {
        case accepted
        case message
        case state
        case currentStep = "current_step"
        case eventCount = "event_count"
    }
}

// MARK: - Client

final class BackendClient {
    var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "backendURL")
        return stored.flatMap { URL(string: $0) }
            ?? URL(string: "http://127.0.0.1:8000")!
    }

    // MARK: Detection

    /// Gloves and hands only.
    func detect(image: UIImage) async throws -> DetectResponse {
        try await upload(image, to: "detect")
    }

    /// Instruments and tray state only.
    func detectTray(image: UIImage) async throws -> TrayDetectResponse {
        try await upload(image, to: "detect-tray")
    }

    /// PPE, instruments, and tray state from one upload. Throws
    /// `BackendError.endpointMissing` against a backend that predates
    /// /analyze, so the caller can fall back to the two older endpoints.
    func analyze(image: UIImage) async throws -> AnalyzeResponse {
        try await upload(image, to: "analyze")
    }

    /// Detection has to keep pace with a live camera feed. A request that
    /// hasn't answered in this long is treated as a failure so the app can
    /// fall back to on-device detection instead of stalling on the default
    /// 60-second timeout.
    private static let detectionTimeout: TimeInterval = 8

    private func upload<Response: Decodable>(_ image: UIImage, to path: String) async throws -> Response {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw BackendError.imageEncodingFailed
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.detectionTimeout

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.badResponse
        }
        if http.statusCode == 404 || http.statusCode == 405 {
            throw BackendError.endpointMissing
        }
        guard http.statusCode == 200 else {
            throw BackendError.badResponse
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: Health

    func health() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: Settings

    func getSettings() async throws -> BackendSettings {
        let url = baseURL.appendingPathComponent("settings")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(BackendSettings.self, from: data)
    }

    func updateConfidenceThreshold(_ value: Double) async throws -> BackendSettings {
        let url = baseURL.appendingPathComponent("settings")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["confidence_threshold": value])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(BackendSettings.self, from: data)
    }

    // MARK: Compliance

    func complianceState() async throws -> ComplianceState {
        let url = baseURL.appendingPathComponent("compliance/state")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(ComplianceState.self, from: data)
    }

    func sendComplianceEvent(_ event: String, step: String? = nil) async throws -> ComplianceEventResult {
        let url = baseURL.appendingPathComponent("compliance/event")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: String] = ["event": event]
        if let step { payload["step"] = step }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(ComplianceEventResult.self, from: data)
    }

    func resetCompliance() async throws -> ComplianceState {
        let url = baseURL.appendingPathComponent("compliance/reset")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(ComplianceState.self, from: data)
    }
}

// MARK: - Ask SPAI

struct AskRequest: Codable {
    let question: String
    let station: String
    let stepIndex: Int
    let detectionSummary: String

    enum CodingKeys: String, CodingKey {
        case question, station
        case stepIndex = "step_index"
        case detectionSummary = "detection_summary"
    }
}

struct AskResponse: Codable {
    let answer: String
    let station: String
    let stepIndex: Int

    enum CodingKeys: String, CodingKey {
        case answer, station
        case stepIndex = "step_index"
    }
}

extension BackendClient {
    func ask(_ request: AskRequest) async throws -> AskResponse {
        let url = baseURL.appendingPathComponent("ask")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(AskResponse.self, from: data)
    }
}


enum BackendError: Error {
    case imageEncodingFailed
    case badResponse
    /// The backend is reachable but doesn't have this route (an older deploy).
    case endpointMissing
}
