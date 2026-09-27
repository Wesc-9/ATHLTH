@preconcurrency import CoreLocation
import Foundation

private struct ChallengeLocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let course: Double
    let speed: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy =
            location.horizontalAccuracy
        verticalAccuracy =
            location.verticalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }

    func makeLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: altitude,
            horizontalAccuracy:
                horizontalAccuracy,
            verticalAccuracy:
                verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}

@MainActor
final class ChallengeLocationStore:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate {

    @Published private(set)
    var authorizationStatus:
        CLAuthorizationStatus

    @Published private(set)
    var isLocating = false

    @Published private(set)
    var lastError: String?

    private let manager =
        CLLocationManager()

    private var continuation:
        CheckedContinuation<
            CLLocation?,
            Never
        >?

    override init() {
        authorizationStatus =
            manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy =
            kCLLocationAccuracyBest
    }

    func requestCurrentLocation()
        async -> CLLocation? {

        if let continuation {
            continuation.resume(
                returning: nil
            )
            self.continuation = nil
        }

        lastError = nil

        switch manager.authorizationStatus {
        case .authorizedWhenInUse,
             .authorizedAlways:
            return await locate()

        case .notDetermined:
            return await withCheckedContinuation {
                continuation in

                self.continuation =
                    continuation
                isLocating = true
                manager
                    .requestWhenInUseAuthorization()
            }

        case .denied,
             .restricted:
            lastError =
                "Location access is off. You can still check in manually, but ATHLTH cannot verify that you are near the meetup point."
            return nil

        @unknown default:
            return nil
        }
    }

    private func locate()
        async -> CLLocation? {

        await withCheckedContinuation {
            continuation in

            self.continuation =
                continuation
            isLocating = true
            manager.requestLocation()
        }
    }

    private func handleAuthorization(
        rawValue: Int
    ) {
        guard let status =
            CLAuthorizationStatus(
                rawValue: Int32(rawValue)
            )
        else {
            return
        }

        authorizationStatus = status

        guard let continuation
        else {
            return
        }

        switch status {
        case .authorizedWhenInUse,
             .authorizedAlways:
            self.continuation = nil
            manager.requestLocation()
            self.continuation =
                continuation

        case .denied,
             .restricted:
            self.continuation = nil
            isLocating = false
            lastError =
                "Location access is off. You can still check in manually, but ATHLTH cannot verify that you are near the meetup point."
            continuation.resume(
                returning: nil
            )

        case .notDetermined:
            break

        @unknown default:
            self.continuation = nil
            isLocating = false
            continuation.resume(
                returning: nil
            )
        }
    }

    private func finishLocation(
        _ sample:
            ChallengeLocationSample?
    ) {
        guard let continuation
        else {
            return
        }

        self.continuation = nil
        isLocating = false
        continuation.resume(
            returning:
                sample?.makeLocation()
        )
    }

    private func finishLocation(
        errorMessage: String
    ) {
        guard let continuation
        else {
            return
        }

        self.continuation = nil
        isLocating = false
        lastError = errorMessage
        continuation.resume(
            returning: nil
        )
    }

    nonisolated func
        locationManagerDidChangeAuthorization(
            _ manager: CLLocationManager
        ) {
        let rawValue =
            Int(
                manager.authorizationStatus
                    .rawValue
            )

        Task { @MainActor [weak self] in
            self?.handleAuthorization(
                rawValue: rawValue
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations
            locations: [CLLocation]
    ) {
        let recent =
            locations
                .filter {
                    $0.horizontalAccuracy >= 0 &&
                    $0.horizontalAccuracy <= 100
                }
                .sorted {
                    $0.timestamp >
                    $1.timestamp
                }
                .first
                .map(
                    ChallengeLocationSample
                        .init
                )

        Task { @MainActor [weak self] in
            self?.finishLocation(recent)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let message =
            error.localizedDescription

        Task { @MainActor [weak self] in
            self?.finishLocation(
                errorMessage: message
            )
        }
    }
}
