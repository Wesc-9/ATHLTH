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
    @State private var followMe = true
    @State private var routeCamera:
        MapCameraPosition = .automatic

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

                        }
                        if workout.resumedAt == nil { Button("Resume workout") { recorder.resume() } }
                        else { Button("Pause workout") { recorder.pause() } }
                        Button("Finish & save", role: .destructive) {
                            confirmFinish = true
                        }
                        .disabled(recorder.saving)
                    }

                    if let ghostTitle =
                            workout.ghostRaceTitle,
                       let distanceDelta =
                            workout
                                .ghostDistanceDeltaMeters {
                        Section("Ghost") {
                            HStack(
                                alignment:
                                    .firstTextBaseline
                            ) {
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(ghostTitle)
                                        .font(.headline)

                                    Text(
                                        "Live comparison"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }

                                Spacer()

                                Text(
                                    liveGhostText(
                                        distanceDelta
                                    )
                                )
                                .font(
                                    .title3
                                        .weight(.bold)
                                )
                                .monospacedDigit()
                                .foregroundStyle(
                                    abs(distanceDelta) <
                                        8
                                        ? .secondary
                                        : distanceDelta >= 0
                                            ? ATHLTHTheme
                                                .vitality
                                            : .orange
                                )
                            }

                            if let timeDelta =
                                    workout
                                        .ghostTimeDeltaSeconds {
                                LabeledContent(
                                    "Estimated gap",
                                    value:
                                        ghostTimeText(
                                            timeDelta
                                        )
                                )
                            }

                            if workout
                                .ghostAudioConfiguration?
                                .enabled == true {
                                Label(
                                    "Ghost Updates active",
                                    systemImage:
                                        "waveform"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                    }

                    if workout.plannedRouteTitle != nil {
                        Section("Route Guardian") {
                            HStack {
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        workout
                                            .plannedRouteTitle ??
                                        "Route"
                                    )
                                    .font(
                                        .headline
                                    )

                                    if let remaining =
                                        workout
                                            .routeRemainingMeters {
                                        Text(
                                            routeDistanceText(
                                                remaining
                                            ) +
                                            " remaining"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }

                                Spacer()

                                if let progress =
                                    workout
                                        .routeProgressPercent {
                                    Text(
                                        "\(Int(progress.rounded()))%"
                                    )
                                    .font(
                                        .title3
                                            .weight(.bold)
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        ATHLTHTheme.vitality
                                    )
                                }
                            }

                            if let progress =
                                workout
                                    .routeProgressPercent {
                                ProgressView(
                                    value:
                                        min(
                                            max(
                                                progress,
                                                0
                                            ),
                                            100
                                        ),
                                    total: 100
                                )
                                .tint(
                                    ATHLTHTheme.vitality
                                )
                            }

                            if let deviation =
                                workout
                                    .routeDeviationMeters {
                                let threshold =
                                    workout
                                        .routeAlertConfiguration?
                                        .deviationMeters ??
                                    80
                                Label(
                                    deviation > threshold
                                        ? "\(Int(deviation.rounded())) m off route"
                                        : "On route",
                                    systemImage:
                                        deviation > threshold
                                            ? "exclamationmark.triangle.fill"
                                            : "location.fill"
                                )
                                .foregroundStyle(
                                    deviation > threshold
                                        ? .orange
                                        : ATHLTHTheme
                                            .vitality
                                )
                            }

                            if let bearing =
                                workout
                                    .routeNextBearingDegrees {
                                HStack {
                                    Image(
                                        systemName:
                                            "location.north.fill"
                                    )
                                    .rotationEffect(
                                        .degrees(
                                            bearing
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.vitality
                                    )

                                    Text(
                                        "Next route segment"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }

                            if let toStart =
                                workout
                                    .routeDistanceToStartMeters,
                               toStart > 250,
                               (
                                    workout
                                        .routeProgressPercent ??
                                    0
                               ) < 3 {
                                Button {
                                    openDirectionsToStart(
                                        workout
                                    )
                                } label: {
                                    Label(
                                        routeDistanceText(
                                            toStart
                                        ) +
                                        " to start · Directions",
                                        systemImage:
                                            "arrow.triangle.turn.up.right.diamond.fill"
                                    )
                                }
                            }
                        }
                    }

                    if let step =
                        recorder.currentStructuredStep {
                        Section("Workout step") {
                            TimelineView(
                                .periodic(
                                    from: .now,
                                    by: 1
                                )
                            ) { context in
                                let progress =
                                    recorder
                                        .currentStructuredStepProgress(
                                            at:
                                                context.date
                                        )

                                VStack(
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    HStack {
                                        Text(step.title)
                                            .font(
                                                .headline
                                            )

                                        Spacer()

                                        if let active =
                                            recorder.active,
                                           let plan =
                                            active
                                                .structuredRunningWorkout {
                                            Text(
                                                "Step \((active.structuredStepIndex ?? 0) + 1) / \(plan.steps.count)"
                                            )
                                            .font(
                                                .caption
                                                    .weight(
                                                        .semibold
                                                    )
                                            )
                                            .foregroundStyle(
                                                .secondary
                                            )
                                        }
                                    }

                                    ProgressView(
                                        value: progress
                                    )
                                    .tint(
                                        ATHLTHTheme.accent
                                    )

                                    Text(
                                        structuredRemainingText(
                                            step: step,
                                            workout:
                                                workout,
                                            date:
                                                context.date
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )

                                    if let next =
                                        recorder
                                            .nextStructuredStep {
                                        Label(
                                            "Next: \(next.title)",
                                            systemImage:
                                                "arrow.right.circle.fill"
                                        )
                                        .font(
                                            .caption
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                    }
                                }
                            }
                        }
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
                                position: $routeCamera
                            ) {
                                if let route =
                                    workout.plannedRouteCoordinates,
                                   route.count >= 2 {
                                    MapPolyline(
                                        coordinates:
                                            displayRouteCoordinates(
                                                route
                                            )
                                    )
                                    .stroke(
                                        ATHLTHTheme.vitality,
                                        lineWidth: 6
                                    )
                                }

                                if workout.points.count >= 2 {
                                    MapPolyline(
                                        coordinates:
                                            displayWorkoutCoordinates(
                                                workout.points
                                            )
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
                            .frame(height: 300)
                            .mapControls {
                                MapCompass()
                                MapScaleView()
                            }
                            .onAppear {
                                routeCamera =
                                    .region(
                                        workoutMapRegion(
                                            for: workout
                                        )
                                    )
                            }
                            .onChange(
                                of:
                                    recorder
                                        .active?
                                        .points
                                        .count
                            ) { _, _ in
                                guard followMe,
                                      let last =
                                        recorder
                                            .active?
                                            .points
                                            .last
                                else {
                                    return
                                }

                                routeCamera =
                                    .region(
                                        followRegion(
                                            around:
                                                last
                                                    .location
                                                    .coordinate
                                        )
                                    )
                            }

                            HStack {
                                Button {
                                    followMe.toggle()

                                    if followMe,
                                       let last =
                                        recorder
                                            .active?
                                            .points
                                            .last {
                                        routeCamera =
                                            .region(
                                                followRegion(
                                                    around:
                                                        last
                                                            .location
                                                            .coordinate
                                                )
                                            )
                                    }
                                } label: {
                                    Label(
                                        followMe
                                            ? "Following"
                                            : "Follow me",
                                        systemImage:
                                            followMe
                                                ? "location.fill"
                                                : "location"
                                    )
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button {
                                    routeCamera =
                                        .region(
                                            workoutMapRegion(
                                                for: workout
                                            )
                                        )
                                    followMe = false
                                } label: {
                                    Label(
                                        "Show route",
                                        systemImage:
                                            "map"
                                    )
                                }
                                .buttonStyle(.bordered)
                            }

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
                if let completion =
                    recorder.lastRouteCompletion {
                    Section("Route complete") {
                        HStack {
                            completionMetric(
                                title: "MATCH",
                                value:
                                    "\(Int(completion.routeMatchPercent.rounded()))%"
                            )
                            completionMetric(
                                title: "AVG DEV.",
                                value:
                                    "\(Int(completion.averageDeviationMeters.rounded())) m"
                            )
                            completionMetric(
                                title: "MAX DEV.",
                                value:
                                    "\(Int(completion.maxDeviationMeters.rounded())) m"
                            )
                        }

                        if completion.personalBest {
                            Label(
                                "New personal best",
                                systemImage:
                                    "trophy.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .premiumGold
                            )
                        }

                        if let rank =
                                completion
                                    .leaderboardRank,
                           let fieldSize =
                                completion
                                    .leaderboardFieldSize {
                            Label(
                                "Leaderboard #\(rank) of \(fieldSize)",
                                systemImage:
                                    "list.number"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme.vitality
                            )
                        } else {
                            Label(
                                completion.leaderboardEligible
                                    ? "Eligible for route leaderboard"
                                    : "Route match was below leaderboard requirements",
                                systemImage:
                                    completion.leaderboardEligible
                                        ? "checkmark.seal.fill"
                                        : "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                completion.leaderboardEligible
                                    ? ATHLTHTheme.vitality
                                    : .secondary
                            )
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

    private func displayRouteCoordinates(
        _ coordinates: [RouteCoordinate]
    ) -> [CLLocationCoordinate2D] {
        let sorted =
            coordinates.sorted {
                $0.sequence < $1.sequence
            }

        guard sorted.count > 800 else {
            return sorted.map(\.coordinate)
        }

        let step =
            max(
                sorted.count / 800,
                1
            )
        var sampled =
            stride(
                from: 0,
                to: sorted.count,
                by: step
            )
            .map {
                sorted[$0].coordinate
            }

        if let last = sorted.last?.coordinate,
           sampled.last?.latitude !=
                last.latitude ||
            sampled.last?.longitude !=
                last.longitude {
            sampled.append(last)
        }

        return sampled
    }

    private func displayWorkoutCoordinates(
        _ points: [PhoneRoutePoint]
    ) -> [CLLocationCoordinate2D] {
        guard points.count > 600 else {
            return points.map {
                $0.location.coordinate
            }
        }

        let step =
            max(
                points.count / 600,
                1
            )
        var sampled =
            stride(
                from: 0,
                to: points.count,
                by: step
            )
            .map {
                points[$0]
                    .location.coordinate
            }

        if let last =
            points.last?.location.coordinate,
           sampled.last?.latitude !=
                last.latitude ||
            sampled.last?.longitude !=
                last.longitude {
            sampled.append(last)
        }

        return sampled
    }

    private func routeDistanceText(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format: "%.1f km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
    }

    private func structuredRemainingText(
        step: WatchRunningWorkoutStep,
        workout: PhoneWorkout,
        date: Date
    ) -> String {
        switch step.measure {
        case .time:
            guard let target =
                step.durationSeconds
            else {
                return "Open step"
            }

            let used =
                max(
                    workout.elapsed(at: date) -
                        (
                            workout
                                .structuredStepStartElapsedTime ??
                            0
                        ),
                    0
                )
            let remaining =
                max(target - used, 0)

            return
                "\(Int(remaining.rounded())) sec remaining"

        case .distance:
            guard let target =
                step.distanceMeters
            else {
                return "Open step"
            }

            let used =
                max(
                    workout.distanceMeters -
                        (
                            workout
                                .structuredStepStartDistanceMeters ??
                            0
                        ),
                    0
                )

            return routeDistanceText(
                max(target - used, 0)
            ) + " remaining"

        case .open:
            return "Open step · advance by finishing the workout"
        }
    }

    private func followRegion(
        around coordinate:
            CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span:
                MKCoordinateSpan(
                    latitudeDelta: 0.008,
                    longitudeDelta: 0.008
                )
        )
    }

    private func openDirectionsToStart(
        _ workout: PhoneWorkout
    ) {
        guard let first =
                workout
                    .plannedRouteCoordinates?
                    .min(
                        by: {
                            $0.sequence <
                                $1.sequence
                        }
                    )
        else {
            return
        }

        let item =
            MKMapItem(
                placemark:
                    MKPlacemark(
                        coordinate:
                            CLLocationCoordinate2D(
                                latitude:
                                    first.latitude,
                                longitude:
                                    first.longitude
                            )
                    )
            )

        item.name =
            (workout.plannedRouteTitle ??
                "Route") +
            " · Start"

        item.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey:
                    MKLaunchOptionsDirectionsModeWalking
            ]
        )
    }

    @ViewBuilder
    private func completionMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .monospacedDigit()

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private func ghostTimeText(
        _ seconds: TimeInterval
    ) -> String {
        let amount =
            max(
                Int(
                    abs(seconds)
                        .rounded()
                ),
                0
            )
        let minutes = amount / 60
        let remainder = amount % 60
        let value =
            String(
                format:
                    "%d:%02d",
                minutes,
                remainder
            )

        if abs(seconds) < 1 {
            return "Even"
        }

        return seconds >= 0
            ? "\(value) ahead"
            : "\(value) behind"
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
                    visibility: visibility,
                    routeKey:
                        workout
                            .plannedComparisonRouteID,
                    routeDistanceMeters:
                        workout
                            .plannedRouteDistanceKilometers
                            .map {
                                max(
                                    $0 * 1_000,
                                    0
                                )
                            },
                    routeTitle:
                        workout
                            .plannedRouteTitle
                )
        }

        await realtime.publishLocation(
            lastPoint,
            distanceMeters:
                workout.distanceMeters,
            elapsedSeconds:
                workout.elapsed(at: Date()),
            routeProgressPercent:
                workout.routeProgressPercent,
            routeDeviationMeters:
                workout.routeDeviationMeters,
            routeKey:
                workout
                    .plannedComparisonRouteID,
            routeDistanceMeters:
                workout
                    .plannedRouteDistanceKilometers
                    .map {
                        max(
                            $0 * 1_000,
                            0
                        )
                    },
            routeTitle:
                workout
                    .plannedRouteTitle
        )
    }
}
