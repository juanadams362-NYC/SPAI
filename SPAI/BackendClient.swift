//
//  BackendClient.swift
//  SPAI
//
//  SCRUM-44: Networking layer that talks to the FastAPI backend.
//  Sends an image to /detect and parses the JSON response into Swift.
//  Reusable by both the iOS demo and the visionOS app.
//

import Foundation
import UIKit

/// One detection returned by the backend. Matches the JSON shape from /detect.
struct BackendDetection: Codable, Identifiable {
    var id = UUID()
    let classId: Int
    let className: String
    let confidence: Double
    let box: [Int]   // [x1, y1, x2, y2] in pixel coordinates

    // Map snake_case JSON keys to Swift camelCase.
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

/// Talks to the SPAI backend.
final class BackendClient {
    // Change this if the backend runs elsewhere. localhost for dev.
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
    }

    /// Send an image to /detect and return the parsed detections.
    func detect(image: UIImage) async throws -> DetectResponse {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw BackendError.imageEncodingFailed
        }

        let url = baseURL.appendingPathComponent("detect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Build a multipart/form-data body — the format /detect expects.
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
}

enum BackendError: Error {
    case imageEncodingFailed
    case badResponse
}
