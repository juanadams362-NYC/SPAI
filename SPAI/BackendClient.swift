//
//  BackendClient.swift
//  SPAI
//
//  Networking layer that talks to the FastAPI backend. Covers detection,
//  tray-state detection, health/metrics, runtime settings, and the
//  compliance FSM. Reusable by both the iOS demo and the visionOS app.
//

import Foundation
import UIKit

// MARK: - Detection models

/// One detection returned by the backend. Matches the JSON shape from /detect.
struct BackendDetection: Codable, Identifiable {
    var id = UUID()
    let classId: Int
    let className: String
    let confidence: Double
    let box: [Int]   // [x1, y1, x2, y2] in pixel coordinates

    enum CodingKeys: String, CodingKey {
        case classId = "class_id"
        case className = "class_name"
        case confidence
        case box
    }
}

/// The full /detect response.
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

/// The /detect-tray response — detections plus the loaded/empty verdict.
struct TrayDetectResponse: Codable {
    let detections: [BackendDetection]
    let inferenceTimeMs: Int
    let mode: String
    let instrumentCount: Int
    let trayState: String   // "loaded" or "empty"

    enum CodingKeys: String, CodingKey {
        case detections
        case inferenceTimeMs = "inference_time_ms"
        case mode
        case instrumentCount = "instrument_count"
        case trayState = "tray_state"
    }
}

// MARK: - Settings models

/// The /settings response.
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

/// The current FSM state, from /compliance/state and /compliance/event.
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

/// The result of posting an event, which adds accepted/message on top of state.
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

/// Talks to the SPAI backend.
final class BackendClient {
    // Re-read on every access so a URL change in Settings takes effect
    // on the very next request. Storing this once at init froze the app
    // to whatever URL it launched with.
    var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "backendURL")
        return stored.flatMap { URL(string: $0) }
            ?? URL(string: "http://127.0.0.1:8000")!
    }

    // MARK: Detection

    /// Send an image to /detect and return the parsed detections.
    func detect(image: UIImage) async throws -> DetectResponse {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw BackendError.imageEncodingFailed
        }

        let url = baseURL.appendingPathComponent("detect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendError.badResponse
        }

        return try JSONDecoder().decode(DetectResponse.self, from: data)
    }

    /// Send an image to /detect-tray and return the instruments + tray state.
    /// Same multipart upload as detect(), just a different endpoint and
    /// response type (which includes instrument_count and tray_state).
    func detectTray(image: UIImage) async throws -> TrayDetectResponse {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw BackendError.imageEncodingFailed
        }

        let url = baseURL.appendingPathComponent("detect-tray")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendError.badResponse
        }

        return try JSONDecoder().decode(TrayDetectResponse.self, from: data)
    }

    // MARK: Health

    /// Quick health check — returns true if the backend is reachable.
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

    /// Read the current runtime settings from /settings.
    func getSettings() async throws -> BackendSettings {
        let url = baseURL.appendingPathComponent("settings")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(BackendSettings.self, from: data)
    }

    /// Update the confidence threshold via PATCH /settings.
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

    /// Read the current FSM state from /compliance/state.
    func complianceState() async throws -> ComplianceState {
        let url = baseURL.appendingPathComponent("compliance/state")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.badResponse
        }
        return try JSONDecoder().decode(ComplianceState.self, from: data)
    }

    /// Send an event to the FSM via POST /compliance/event.
    /// `step` is required for start/complete events, nil for contamination/acknowledge.
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

    /// Reset the workflow via POST /compliance/reset.
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

enum BackendError: Error {
    case imageEncodingFailed
    case badResponse
}
