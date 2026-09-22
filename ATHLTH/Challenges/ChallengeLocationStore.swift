import CoreLocation
import Foundation

@MainActor
final class ChallengeLocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isLocating = false
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() async -> CLLocation? {
        if let continuation {
            continuation.resume(returning: nil)
            self.continuation = nil
        }

        lastError = nil

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return await locate()

        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                isLocating = true
                manager.requestWhenInUseAuthorization()
            }

        case .denied, .restricted:
            lastError = "Location access is off. You can still check in manually, but ATHLTH cannot verify that you are near the meetup point."
            return nil

        @unknown default:
            return nil
        }
    }

    private func locate() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isLocating = true
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        guard let continuation else { return }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.continuation = nil
            manager.requestLocation()
            self.continuation = continuation

        case .denied, .restricted:
            self.continuation = nil
            isLocating = false
            lastError = "Location access is off. You can still check in manually, but ATHLTH cannot verify that you are near the meetup point."
            continuation.resume(returning: nil)

        case .notDetermined:
            break

        @unknown default:
            self.continuation = nil
            isLocating = false
            continuation.resume(returning: nil)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let continuation else { return }

        let recent = locations
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 100 }
            .sorted { $0.timestamp > $1.timestamp }
            .first

        self.continuation = nil
        isLocating = false
        continuation.resume(returning: recent)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        guard let continuation else { return }

        self.continuation = nil
        isLocating = false
        lastError = error.localizedDescription
        continuation.resume(returning: nil)
    }
}
