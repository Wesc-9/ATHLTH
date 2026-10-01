import Combine
@preconcurrency import CoreLocation
import Foundation

struct HomeWeatherSnapshot: Equatable {
    let temperatureCelsius: Double
    let symbolName: String
    let locationName: String?
    let observedAt: Date
}

private struct HomeWeatherLocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        timestamp = location.timestamp
    }

    var location: CLLocation {
        CLLocation(
            latitude: latitude,
            longitude: longitude
        )
    }
}

private struct OpenMeteoCurrentWeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    let current: Current
}

@MainActor
final class HomeWeatherStore:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate {

    @Published private(set)
    var snapshot: HomeWeatherSnapshot?

    @Published private(set)
    var isLoading = false

    private let locationManager = CLLocationManager()
    private var lastSuccessfulFetchAt: Date?
    private var lastCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy =
            kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 5_000
    }

    func refreshIfNeeded(
        force: Bool = false
    ) {
        if !force,
           let lastSuccessfulFetchAt,
           Date().timeIntervalSince(
                lastSuccessfulFetchAt
           ) < 30 * 60,
           snapshot != nil {
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways,
             .authorizedWhenInUse:
            isLoading = true
            locationManager.requestLocation()

        case .notDetermined:
            // Weather is visible on Home, so request the same when-in-use
            // permission ATHLTH already uses for nearby routes and workouts.
            locationManager
                .requestWhenInUseAuthorization()

        case .denied,
             .restricted:
            isLoading = false

        @unknown default:
            isLoading = false
        }
    }

    nonisolated func
        locationManagerDidChangeAuthorization(
            _ manager: CLLocationManager
        ) {
        let rawValue =
            Int(manager.authorizationStatus.rawValue)

        Task { @MainActor [weak self] in
            guard let self,
                  let status =
                    CLAuthorizationStatus(
                        rawValue: Int32(rawValue)
                    )
            else {
                return
            }

            switch status {
            case .authorizedAlways,
                 .authorizedWhenInUse:
                self.isLoading = true
                self.locationManager
                    .requestLocation()

            case .denied,
                 .restricted:
                self.isLoading = false

            case .notDetermined:
                break

            @unknown default:
                self.isLoading = false
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let sample =
            locations
                .filter {
                    $0.horizontalAccuracy >= 0 &&
                    $0.horizontalAccuracy <= 10_000
                }
                .max {
                    $0.timestamp < $1.timestamp
                }
                .map(HomeWeatherLocationSample.init)

        guard let sample else {
            Task { @MainActor [weak self] in
                self?.isLoading = false
            }
            return
        }

        Task { @MainActor [weak self] in
            await self?.loadWeather(
                at: sample
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isLoading = false
        }
    }

    private func loadWeather(
        at sample: HomeWeatherLocationSample
    ) async {
        let coordinate = CLLocationCoordinate2D(
            latitude: sample.latitude,
            longitude: sample.longitude
        )

        if let lastCoordinate,
           let lastSuccessfulFetchAt,
           Date().timeIntervalSince(
                lastSuccessfulFetchAt
           ) < 30 * 60 {
            let previous = CLLocation(
                latitude: lastCoordinate.latitude,
                longitude: lastCoordinate.longitude
            )

            if previous.distance(
                from: sample.location
            ) < 5_000,
               snapshot != nil {
                isLoading = false
                return
            }
        }

        defer {
            isLoading = false
        }

        var components = URLComponents(
            string:
                "https://api.open-meteo.com/v1/forecast"
        )
        components?.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: String(
                    format: "%.4f",
                    sample.latitude
                )
            ),
            URLQueryItem(
                name: "longitude",
                value: String(
                    format: "%.4f",
                    sample.longitude
                )
            ),
            URLQueryItem(
                name: "current",
                value:
                    "temperature_2m,weather_code"
            ),
            URLQueryItem(
                name: "temperature_unit",
                value: "celsius"
            )
        ]

        guard let url = components?.url else {
            return
        }

        do {
            let (data, response) =
                try await URLSession.shared.data(
                    from: url
                )

            guard let http =
                    response as? HTTPURLResponse,
                  (200..<300).contains(
                    http.statusCode
                  )
            else {
                return
            }

            let decoded =
                try JSONDecoder().decode(
                    OpenMeteoCurrentWeatherResponse.self,
                    from: data
                )

            let locationName =
                await reverseGeocodedName(
                    sample.location
                )

            snapshot = HomeWeatherSnapshot(
                temperatureCelsius:
                    decoded.current.temperature,
                symbolName:
                    Self.symbolName(
                        for: decoded.current.weatherCode
                    ),
                locationName: locationName,
                observedAt: Date()
            )
            lastSuccessfulFetchAt = Date()
            lastCoordinate = coordinate
        } catch {
            // Weather is an optional Home enhancement. Keep the last
            // successful value rather than surfacing network noise.
        }
    }

    private func reverseGeocodedName(
        _ location: CLLocation
    ) async -> String? {
        do {
            let placemarks =
                try await CLGeocoder()
                    .reverseGeocodeLocation(
                        location
                    )

            let place = placemarks.first
            return place?.locality ??
                place?.subAdministrativeArea ??
                place?.administrativeArea
        } catch {
            return nil
        }
    }

    private static func symbolName(
        for code: Int
    ) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67,
             80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77,
             85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}
