import MapKit
import SwiftUI

/// An advisory walking route, separate from the workout's recorded course.
struct WatchWalkingDirectionsRequest: Identifiable {
    let id = UUID()
    let destination: CLLocationCoordinate2D
    let isRecovery: Bool
    let workoutRouteID: UUID?

    var isValid: Bool {
        CLLocationCoordinate2DIsValid(destination) &&
        destination.latitude.isFinite && destination.longitude.isFinite
    }
}

@available(watchOS 26.0, *)
struct WatchWalkingDirectionsView: View {
    let request: WatchWalkingDirectionsRequest
    var isStillRelevant: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var result: MKRoute?
    @State private var calculation: MKDirections?
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var failed = false
    @State private var calculatedAt: Date?
    @State private var generation = UUID()

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(request.isRecovery ? tr("Back to route", "Tilbake til ruten") : tr("Way to start", "Veien til start"))
                    .font(.headline)
                Text(tr("Apple Maps calculates a walking route using your location. Your ATHLTH course and workout stay unchanged.", "Apple Kart beregner en gangvei fra posisjonen din. ATHLTH-ruten og treningsøkten endres ikke."))
                    .font(.caption2).foregroundStyle(WatchTheme.muted)
                if busy {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let result, let calculatedAt {
                    Map {
                        MapPolyline(result.polyline).stroke(WatchTheme.premiumGold, lineWidth: 4)
                        Marker(tr("Destination", "Målpunkt"), coordinate: request.destination)
                    }
                    .frame(height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(ATHLTHWorkoutSummaryEngine.distanceText(result.distance))
                        .font(.title3.weight(.semibold))
                    Text(tr("Estimated walking time", "Estimert gangtid") + ": " +
                        ATHLTHWorkoutSummaryEngine.durationText(result.expectedTravelTime))
                        .font(.caption2)
                    HStack {
                        Text(tr("Calculated", "Beregnet"))
                        Text(calculatedAt, style: .time)
                    }.font(.caption2).foregroundStyle(WatchTheme.muted)
                    Text(tr("Route preview, not live turn-by-turn navigation. Recalculate if you move.", "Ruteforslag, ikke løpende svingnavigasjon. Beregn på nytt dersom du har flyttet deg."))
                        .font(.caption2).foregroundStyle(WatchTheme.muted)
                    ForEach(Array(result.steps.filter { !$0.instructions.isEmpty }.prefix(8).enumerated()), id: \.offset) { step in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.element.instructions).font(.caption2)
                            Text(ATHLTHWorkoutSummaryEngine.distanceText(step.element.distance))
                                .font(.system(size: 9)).foregroundStyle(WatchTheme.muted)
                        }
                    }
                }
                if failed {
                    Text(tr("Walking directions unavailable. Your saved course and offline guidance still work.", "Gangvei er utilgjengelig. Lagret rute og lokal ruteveiledning fungerer fortsatt."))
                        .font(.caption2).foregroundStyle(WatchTheme.muted)
                }
                Button(result == nil ? tr("Calculate walking route", "Beregn gangvei") : tr("Recalculate", "Beregn på nytt")) {
                    calculate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !request.isValid)
                Button(tr("Close", "Lukk"), role: .cancel) { dismiss() }
            }
        }
        .padding(.horizontal, 4)
        .onDisappear { cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancel(); result = nil; calculatedAt = nil }
        }
    }

    private func cancel() {
        generation = UUID()
        task?.cancel()
        calculation?.cancel()
        task = nil
        calculation = nil
        busy = false
    }

    private func calculate() {
        guard request.isValid, isStillRelevant(), !busy else {
            failed = true
            result = nil
            return
        }
        cancel()
        result = nil
        failed = false
        calculatedAt = nil
        let query = MKDirections.Request()
        query.source = MKMapItem.forCurrentLocation()
        query.destination = MKMapItem(location: CLLocation(latitude: request.destination.latitude,
            longitude: request.destination.longitude), address: nil)
        query.transportType = .walking
        let directions = MKDirections(request: query)
        calculation = directions
        busy = true
        let token = generation
        task = Task { @MainActor in
            do {
                let response = try await directions.calculate()
                guard !Task.isCancelled, generation == token else { return }
                if isStillRelevant(), let route = response.routes.first,
                   route.distance.isFinite, route.distance > 0,
                   route.expectedTravelTime.isFinite, route.expectedTravelTime >= 0 {
                    result = route
                    calculatedAt = Date()
                } else { failed = true }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                failed = true
            }
            busy = false
            calculation = nil
        }
    }
}
