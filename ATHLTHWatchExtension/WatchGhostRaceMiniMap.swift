import CoreLocation
import MapKit
import SwiftUI

/// Watch-sized local map for a prepared Ghost Race.
///
/// The Watch already owns the GPS workout and interpolates its fixed Ghost
/// along the same planned course. This view only presents that state. It does
/// not create a competing opponent timer, modify HealthKit or transmit GPS.
struct WatchGhostRaceMiniMap: View {
    @ObservedObject var workoutManager: WatchWorkoutManager
    var height: CGFloat = 150

    @State private var camera: MapCameraPosition = .automatic
    @State private var lastFollowUpdate: Date?

    private let runnerInk = Color(red: 0.16, green: 0.27, blue: 0.40)
    private let ghostGold = Color(red: 0.79, green: 0.47, blue: 0.20)

    private var plannedRoute: [CLLocationCoordinate2D] {
        workoutManager.plannedRoute?.points
            .sorted { $0.sequence < $1.sequence }
            .map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            } ?? []
    }

    private var liveTrail: [CLLocationCoordinate2D] {
        let points = workoutManager.routePoints
            .sorted { $0.sequence < $1.sequence }
        guard !points.isEmpty else { return [] }
        let step = max(points.count / 150, 1)
        var sampled = stride(from: 0, to: points.count, by: step)
            .map {
                CLLocationCoordinate2D(
                    latitude: points[$0].latitude,
                    longitude: points[$0].longitude
                )
            }
        if let last = points.last, sampled.last?.latitude != last.latitude ||
            sampled.last?.longitude != last.longitude {
            sampled.append(
                CLLocationCoordinate2D(
                    latitude: last.latitude,
                    longitude: last.longitude
                )
            )
        }
        return sampled
    }

    private func freshPositions(at now: Date) -> (
        runner: CLLocationCoordinate2D,
        ghost: CLLocationCoordinate2D
    )? {
        guard workoutManager.state == .running,
              let updated = workoutManager.ghostMapUpdatedAt,
              now.timeIntervalSince(updated) >= -5,
              now.timeIntervalSince(updated) <= 12,
              let runnerLat = workoutManager.ghostMapUserLatitude,
              let runnerLon = workoutManager.ghostMapUserLongitude,
              let ghostLat = workoutManager.ghostMapLatitude,
              let ghostLon = workoutManager.ghostMapLongitude,
              (-90...90).contains(runnerLat),
              (-180...180).contains(runnerLon),
              (-90...90).contains(ghostLat),
              (-180...180).contains(ghostLon),
              runnerLat.isFinite, runnerLon.isFinite,
              ghostLat.isFinite, ghostLon.isFinite
        else { return nil }
        return (
            CLLocationCoordinate2D(latitude: runnerLat, longitude: runnerLon),
            CLLocationCoordinate2D(latitude: ghostLat, longitude: ghostLon)
        )
    }

    private func freshLead(at now: Date) -> Double? {
        guard workoutManager.state == .running,
              let updated = workoutManager.ghostComparisonUpdatedAt,
              now.timeIntervalSince(updated) >= -5,
              now.timeIntervalSince(updated) <= 12,
              let delta = workoutManager.ghostDistanceDeltaMeters,
              delta.isFinite
        else { return nil }
        return delta
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { timeline in
            let positions = freshPositions(at: timeline.date)
            let lead = freshLead(at: timeline.date)
            VStack(alignment: .leading, spacing: 6) {
                if plannedRoute.count >= 2 || liveTrail.count >= 2 {
                    Map(position: $camera, interactionModes: []) {
                    if plannedRoute.count >= 2 {
                        MapPolyline(coordinates: plannedRoute)
                            .stroke(runnerInk.opacity(0.40), lineWidth: 3)
                    }
                    if liveTrail.count >= 2 {
                        MapPolyline(coordinates: liveTrail)
                            .stroke(runnerInk, lineWidth: 4)
                    }
                    if let positions {
                        Annotation(
                            ATHLTHLocalization.choose(
                                english: "You", norwegian: "Du"
                            ),
                            coordinate: positions.runner
                        ) {
                            runnerMarker
                        }
                        Annotation("Ghost", coordinate: positions.ghost) {
                            ghostMarker
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(alignment: .bottomLeading) {
                    if positions == nil {
                        Text(
                            workoutManager.state == .paused
                                ? ATHLTHLocalization.choose(
                                    english: "Paused", norwegian: "Pauset"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Waiting for GPS",
                                    norwegian: "Venter på GPS"
                                )
                        )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(7)
                    }
                }
                .onAppear {
                    camera = .region(fallbackRegion)
                    centerIfPossible(at: timeline.date, force: true)
                }
                .onChange(of: workoutManager.ghostMapRevision) { _, _ in
                    centerIfPossible(at: .now)
                }
                .onChange(of: workoutManager.plannedRoute?.id) { _, _ in
                    lastFollowUpdate = nil
                    camera = .region(fallbackRegion)
                    centerIfPossible(at: .now, force: true)
                }
                } else {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Preparing Ghost course",
                            norwegian: "Klargjør Ghost-løypen"
                        ),
                        systemImage: "map"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(
                        WatchTheme.canvas,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                }

                HStack(spacing: 6) {
                    legend(
                        ATHLTHLocalization.choose(english: "You", norwegian: "Du"),
                        color: runnerInk
                    )
                    legend("Ghost", color: ghostGold)
                    Spacer(minLength: 2)
                    if let lead {
                        Text(gapLabel(lead))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    } else {
                        Text("—")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WatchTheme.muted)
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english: "Comparison unavailable",
                                    norwegian: "Sammenligning utilgjengelig"
                                )
                            )
                    }
                }
                .padding(.horizontal, 3)
            }
        }
        .accessibilityIdentifier("watch-ghost-race-live-map")
    }

    private var runnerMarker: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(runnerInk, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .accessibilityLabel(
                ATHLTHLocalization.choose(
                    english: "Your live GPS position",
                    norwegian: "Din GPS-posisjon"
                )
            )
    }

    private var ghostMarker: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(ghostGold, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .accessibilityLabel(
                ATHLTHLocalization.choose(
                    english: "Ghost runner's position",
                    norwegian: "Ghost-løperens posisjon"
                )
            )
    }

    private func legend(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: .medium))
        }
    }

    private func gapLabel(_ meters: Double) -> String {
        if abs(meters) < 8 {
            return ATHLTHLocalization.choose(
                english: "Even", norwegian: "Jevnt"
            )
        }
        return "\(Int(abs(meters).rounded())) m " +
            (meters > 0
                ? ATHLTHLocalization.choose(english: "ahead", norwegian: "foran")
                : ATHLTHLocalization.choose(english: "behind", norwegian: "bak"))
    }

    private func centerIfPossible(at now: Date, force: Bool = false) {
        guard let positions = freshPositions(at: now) else { return }
        if !force, let lastFollowUpdate,
           now.timeIntervalSince(lastFollowUpdate) < 2 { return }

        lastFollowUpdate = now
        camera = .region(Self.runnerRegion(
            positions.runner,
            positions.ghost
        ))
    }

    static func runnerRegion(
        _ runner: CLLocationCoordinate2D,
        _ ghost: CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (runner.latitude + ghost.latitude) / 2,
                longitude: (runner.longitude + ghost.longitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(abs(runner.latitude - ghost.latitude) * 2.6, 0.003),
                longitudeDelta: max(abs(runner.longitude - ghost.longitude) * 2.6, 0.003)
            )
        )
    }

    private var fallbackRegion: MKCoordinateRegion {
        let points = plannedRoute.isEmpty ? liveTrail : plannedRoute
        guard let first = points.first else {
            // No position is shown as live until a trusted GPS sample arrives.
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: 0, longitude: 0
                ),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude
        for point in points.dropFirst() {
            minLatitude = min(minLatitude, point.latitude)
            maxLatitude = max(maxLatitude, point.latitude)
            minLongitude = min(minLongitude, point.longitude)
            maxLongitude = max(maxLongitude, point.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.4, 0.004),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.4, 0.004)
            )
        )
    }
}
