import SwiftUI
import MapKit

struct IPhoneWorkoutView: View {
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmFinish = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Keep your iPhone with you throughout the workout. GPS measures distance and pace outdoors. Heart rate and calories are not estimated.")
                }
                if let workout = recorder.active {
                    Section(workout.title) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = workout.elapsed(at: context.date)
                            LabeledContent("Active time", value: Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                            LabeledContent("Distance", value: settings.measurementPreference.distance(fromKilometers: workout.distanceMeters / 1000))
                            if workout.distanceMeters >= 50 {
                                LabeledContent("Average pace", value: String(format: "%.1f min/%@", elapsed / 60 / (workout.distanceMeters / (settings.measurementPreference == .metric ? 1000 : 1609.344)), settings.measurementPreference.distanceUnit))
                            }

                            if let delta =
                                realtime.liveGhostDeltaMeters(
                                    ownDistanceMeters:
                                        workout.distanceMeters
                                ) {
                                LabeledContent(
                                    "Live Ghost",
                                    value:
                                        liveGhostText(
                                            delta
                                        )
                                )
                            }
                        }
                        if workout.resumedAt == nil { Button("Resume workout") { recorder.resume() } }
                        else { Button("Pause workout") { recorder.pause() } }
                        Button("Finish & save", role: .destructive) {
                            confirmFinish = true
                        }
                        .disabled(recorder.saving)
                    }

                    if let liveSession = realtime.currentSession,
                       realtime.isSharingLiveLocation {
                        Section("Live") {
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: liveSession
                                )
                            } label: {
                                Label(
                                    liveSession.ghostChallengeID == nil
                                        ? "View live workout"
                                        : "View live Ghost Run",
                                    systemImage:
                                        "location.circle.fill"
                                )
                            }

                            Text(
                                liveSession.ghostChallengeID == nil
                                    ? "Your latest position is shared only with the audience selected in Social Privacy."
                                    : "This Ghost Run live position is private to the race participants."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if workout.plannedRouteCoordinates?.count ?? 0 >= 2 ||
                        workout.points.last != nil {
                        Section(
                            workout.plannedRouteTitle == nil
                                ? "Current GPS position"
                                : "Route"
                        ) {
                            Map(
                                initialPosition: .region(
                                    workoutMapRegion(
                                        for: workout
                                    )
                                )
                            ) {
                                if let route =
                                    workout.plannedRouteCoordinates,
                                   route.count >= 2 {
                                    MapPolyline(
                                        coordinates:
                                            route.map(\.coordinate)
                                    )
                                    .stroke(
                                        ATHLTHTheme.vitality,
                                        lineWidth: 6
                                    )
                                }

                                if workout.points.count >= 2 {
                                    MapPolyline(
                                        coordinates:
                                            workout.points.map {
                                                $0.location.coordinate
                                            }
                                    )
                                    .stroke(
                                        ATHLTHTheme.accent,
                                        lineWidth: 4
                                    )
                                }

                                if let last =
                                    workout.points.last {
                                    Marker(
                                        "You",
                                        coordinate:
                                            last.location.coordinate
                                    )
                                }
                            }
                            .frame(height: 260)

                            if let routeTitle =
                                workout.plannedRouteTitle {
                                HStack {
                                    Label(
                                        routeTitle,
                                        systemImage:
                                            "point.topleft.down.to.point.bottomright.curvepath"
                                    )
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )

                                    Spacer()

                                    if let distance =
                                        workout
                                            .plannedRouteDistanceKilometers {
                                        Text(
                                            settings
                                                .measurementPreference
                                                .distance(
                                                    fromKilometers:
                                                        distance
                                                )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if let message = recorder.message { Section { Text(message).font(.footnote) } }
                Section("Saved iPhone workouts") {
                    ForEach(recorder.history.prefix(20)) { workout in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(workout.title).font(.headline)
                            Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                            Text(String(format: "%.2f km · %.0f min", workout.distanceMeters / 1000, workout.accumulatedSeconds / 60))
                            if workout.healthID == nil {
                                Button("Copy to Apple Health") {
                                    Task { await health.requestAuthorization(); await recorder.retryHealthSave(workout) }
                                }.disabled(recorder.saving)
                            } else { Label("Saved to Apple Health", systemImage: "checkmark.circle").font(.caption) }
                        }
                    }
                }
            }
            .navigationTitle("iPhone workout")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog(
                "Finish this workout?",
                isPresented: $confirmFinish,
                titleVisibility: .visible
            ) {
                Button("Finish & save") {
                    Task {
                        await recorder.finish()
                        await realtime
                            .leaveCurrentLiveWorkout()
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(
                        for: .seconds(5)
                    )

                    guard !Task.isCancelled else {
                        break
                    }

                    recorder.checkpoint()
                    await publishLivePointIfNeeded()
                }
            }
        }
    }

    private func workoutMapRegion(
        for workout: PhoneWorkout
    ) -> MKCoordinateRegion {
        let routeCoordinates =
            workout.plannedRouteCoordinates?
                .map(\.coordinate) ?? []
        let recordedCoordinates =
            workout.points.map {
                $0.location.coordinate
            }
        let coordinates =
            routeCoordinates.isEmpty
                ? recordedCoordinates
                : routeCoordinates + recordedCoordinates

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.01,
                        longitudeDelta: 0.01
                    )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude =
                min(minLatitude, coordinate.latitude)
            maxLatitude =
                max(maxLatitude, coordinate.latitude)
            minLongitude =
                min(minLongitude, coordinate.longitude)
            maxLongitude =
                max(maxLongitude, coordinate.longitude)
        }

        let latitudeDelta =
            max(
                (maxLatitude - minLatitude) * 1.28,
                0.008
            )
        let longitudeDelta =
            max(
                (maxLongitude - minLongitude) * 1.28,
                0.008
            )

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (minLatitude + maxLatitude) / 2,
                    longitude:
                        (minLongitude + maxLongitude) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta: latitudeDelta,
                    longitudeDelta: longitudeDelta
                )
        )
    }

    private func liveGhostText(
        _ meters: Double
    ) -> String {
        let amount =
            Int(
                abs(meters)
                    .rounded()
            )

        if abs(meters) < 5 {
            return "Side by side"
        }

        return meters >= 0
            ? "You +\(amount) m"
            : "Ghost +\(amount) m"
    }

    @MainActor
    private func publishLivePointIfNeeded() async {
        guard let workout = recorder.active,
              workout.resumedAt != nil,
              let lastPoint =
                workout.points.last?
                    .location
        else {
            return
        }

        if realtime.currentSession == nil {
            guard social.privacy?
                    .shareLiveWorkoutLocation ==
                    true
            else {
                return
            }

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title: workout.title,
                    activity:
                        workout.walking
                            ? "walking"
                            : "running",
                    visibility: visibility
                )
        }

        await realtime.publishLocation(
            lastPoint,
            distanceMeters:
                workout.distanceMeters,
            elapsedSeconds:
                workout.elapsed(at: Date())
        )
    }
}
