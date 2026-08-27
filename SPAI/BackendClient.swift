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

    enum CodingKeys: String, CodingKey {
        case classId = "class_id"
        case className = "class_name"
        case confidence
        case box
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
}
