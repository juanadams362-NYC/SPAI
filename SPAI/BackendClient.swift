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
    /// The workflow this headset is running. Sent with every request so the
    /// server keeps each headset's state separate; a classroom of headsets
    /// sharing one server must not advance or halt each other's workflow.
    static var sessionID = UUID().uuidString

    var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "backendURL")
        return stored.flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
            ?? URL(string: "http://127.0.0.1:8000")!
    }

    /// Every request goes through here so the site key and session id are
    /// never forgotten on a new endpoint.
    private func makeRequest(_ path: String, method: String = "GET", timeout: TimeInterval = 15) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(Self.sessionID, forHTTPHeaderField: "X-SPAI-Session")
        if let token = SchoolConnection.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest, body: Data? = nil) async throws -> Response {
        var request = request
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
        switch http.statusCode {
        case 200: return
        case 401: throw BackendError.unauthorized
        case 404: throw BackendError.notFound
        case 405: throw BackendError.endpointMissing
        case 429: throw BackendError.rateLimited
        default: throw BackendError.badResponse
        }
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

        var request = makeRequest(path, method: "POST", timeout: Self.detectionTimeout)
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
        try Self.check(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: Health

    /// Whether the server is reachable, and whether this headset is still
    /// paired with a school on it — different problems with different fixes.
    func connection() async -> BackendConnection {
        guard SchoolConnection.shared.isPaired else { return .unpaired }
        var probe = makeRequest("health", timeout: 5)
        probe.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: probe)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .unreachable }
        } catch {
            return .unreachable
        }
        do {
            let me: DeviceInfo = try await send(makeRequest("device/me", timeout: 5))
            SchoolConnection.shared.refresh(school: me.organization.name, headset: me.device.name)
            return .connected
        } catch BackendError.unauthorized {
            // The dashboard disconnected this headset. Forget the dead token
            // so the home screen asks to pair again instead of failing quietly.
            SchoolConnection.shared.forget()
            return .unpaired
        } catch BackendError.notFound {
            return .outdated
        } catch BackendError.endpointMissing {
            return .outdated
        } catch {
            return .unreachable
        }
    }

    func health() async -> Bool {
        await connection() == .connected
    }

    // MARK: Pairing

    /// Trades a one-time code from the dashboard for this headset's token.
    func pair(server: String, code: String, headsetName: String) async throws -> DevicePairing {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed), base.scheme == "https" || base.scheme == "http", base.host != nil else {
            throw BackendError.badAddress
        }
        var request = URLRequest(url: base.appendingPathComponent("device/pair"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code, "name": headsetName])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
        switch http.statusCode {
        case 200: return try JSONDecoder().decode(DevicePairing.self, from: data)
        case 400: throw BackendError.badCode
        case 429: throw BackendError.rateLimited
        case 404, 405: throw BackendError.endpointMissing
        default: throw BackendError.badResponse
        }
    }

    /// Disconnects this headset on the server. Best effort: the local token
    /// is forgotten whatever the server says.
    func unpair() async {
        _ = try? await URLSession.shared.data(for: makeRequest("device/me", method: "DELETE", timeout: 8))
    }

    // MARK: Settings

    func getSettings() async throws -> BackendSettings {
        try await send(makeRequest("settings"))
    }

    // MARK: Compliance

    func complianceState() async throws -> ComplianceState {
        try await send(makeRequest("compliance/state"))
    }

    func sendComplianceEvent(_ event: String, step: String? = nil) async throws -> ComplianceEventResult {
        var payload: [String: String] = ["event": event]
        if let step { payload["step"] = step }
        return try await send(makeRequest("compliance/event", method: "POST"),
                              body: JSONEncoder().encode(payload))
    }

    func resetCompliance() async throws -> ComplianceState {
        try await send(makeRequest("compliance/reset", method: "POST"))
    }

    // MARK: Pilot platform

    /// The class roster, for the sign-in list.
    func learners() async throws -> [Learner] {
        let response: RosterResponse = try await send(makeRequest("learners"))
        return response.learners
    }

    /// Checks a learner's PIN. Throws when the server can't be reached, so
    /// the caller can fall back to checking it when the run is sent.
    func verifyPin(learnerID: String, pin: String) async throws -> PinCheck {
        do {
            return try await send(makeRequest("learners/\(learnerID)/verify-pin", method: "POST", timeout: 8),
                                  body: JSONEncoder().encode(["pin": pin]))
        } catch BackendError.notFound {
            return PinCheck(ok: false, reason: "unknown", attemptsLeft: nil, retryIn: nil)
        }
    }

    /// The institution's station scripts, count sheets and rubric.
    func fetchProtocol() async throws -> SiteProtocol {
        try await send(makeRequest("protocol"))
    }

    /// Uploads a finished run. The server scores it and returns the result
    /// of record. Safe to call again with the same run.
    func uploadRun(_ run: RunRecord) async throws -> ScoredRun {
        try await send(makeRequest("sessions/\(run.id)", method: "PUT", timeout: 20),
                       body: JSONEncoder().encode(run))
    }

    // MARK: Ask SPAI

    func ask(_ question: AskRequest) async throws -> AskResponse {
        try await send(makeRequest("ask", method: "POST", timeout: 30),
                       body: JSONEncoder().encode(question))
    }
}

enum BackendConnection: Equatable {
    case connected
    /// This headset has never been paired with a school, or was disconnected.
    case unpaired
    /// Nothing answered at the school's server address.
    case unreachable
    /// The server is an older version without schools and pairing.
    case outdated
}

struct DeviceInfo: Codable {
    struct Device: Codable { let id: String; let name: String }
    struct Organization: Codable { let id: String; let name: String }
    let device: Device
    let organization: Organization
}

struct DevicePairing: Codable {
    let token: String
    let device: DeviceInfo.Device
    let organization: DeviceInfo.Organization
}

struct PinCheck: Codable, Equatable {
    let ok: Bool
    /// "wrong", "locked" or "unknown" when not ok.
    let reason: String?
    let attemptsLeft: Int?
    let retryIn: Int?

    enum CodingKeys: String, CodingKey {
        case ok, reason
        case attemptsLeft = "attempts_left"
        case retryIn = "retry_in"
    }
}

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

enum BackendError: Error {
    case imageEncodingFailed
    case badResponse
    /// The backend is reachable but doesn't have this route (an older deploy).
    case endpointMissing
    /// This headset isn't paired, or was disconnected from the dashboard.
    case unauthorized
    /// The thing asked about doesn't exist (for a run: the learner was
    /// removed from the roster).
    case notFound
    case rateLimited
    case badCode
    case badAddress
}
