//
//  EnvironmentService.swift
//  SPAI
//

import CoreLocation
import Foundation

/// Live room-adjacent conditions for the detection panel's environment section, sourced from
/// Open-Meteo (no API key/entitlement needed) using the device's approximate location. This is
/// outdoor weather, not an in-room sensor reading — Vision Pro has no public API for that.
@MainActor
@Observable
final class EnvironmentService: NSObject {
    static let shared = EnvironmentService()

    private let locationManager = CLLocationManager()
    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 300

    var temperatureF: Int?
    var humidityPct: Int?
    var lastUpdated: Date?
    var errorMessage: String?

    private override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.delegate = self
    }

    func start() {
        requestFreshReading()
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.refreshInterval))
                self.requestFreshReading()
            }
        }
    }

    private func requestFreshReading() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied"
        @unknown default:
            break
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
        ]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                errorMessage = "Weather request failed"
                return
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            temperatureF = Int(decoded.current.temperature2m.rounded())
            humidityPct = Int(decoded.current.relativeHumidity2m.rounded())
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't reach weather service"
            print("[EnvironmentService] fetch failed: \(error)")
        }
    }
}

extension EnvironmentService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            await self.fetchWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "Location unavailable"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.requestFreshReading()
        }
    }
}

private struct OpenMeteoResponse: Codable {
    struct Current: Codable {
        let temperature2m: Double
        let relativeHumidity2m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
        }
    }
    let current: Current
}
