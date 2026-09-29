import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Activity Center V2
//
// Home deliberately uses one premium activity card at a time. The previous
// Activity Center started several enrichment jobs and rendered realistic 3D
// MapKit snapshots for multiple workouts directly inside the Home feed. This
// replacement keeps the same workout data and detail destinations, but makes
// the Home surface deterministic, light and defensive around GPS input.

struct HomeActivityCenterV2: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    @State private var detail: WorkoutDetail?
    @State private var detailWorkoutID: UUID?
    @State private var showingPublish = false
    @State private var selectedPublishWorkoutID: UUID?

    private var workouts: [SocialPublishableWorkout] {
        let localStrength =
            strength.workoutHistory
                .filter(\.isFinished)
                .map(SocialPublishableWorkout.init)

        let localStrengthIDs = Set(localStrength.map(\.id))

        let healthWorkouts =
            health.workouts
                .map(SocialPublishableWorkout.init)
                .filter {
                    !(
                        $0.activity == .strength &&
                        localStrengthIDs.contains($0.id)
                    )
                }

        return (healthWorkouts + localStrength)
            .sorted { $0.startDate > $1.startDate }
    }

    private var latestWorkout: SocialPublishableWorkout? {
        workouts.first
    }

    private var latestLoadKey: String {
        latestWorkout?.id.uuidString ?? "activity-center-empty"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if social.pendingRequestCount > 0 {
                pendingRequests
            }

            if let workout = latestWorkout {
                workoutCard(workout)
            } else {
                emptyState
            }
        }
        .sheet(
            isPresented: $showingPublish,
            onDismiss: {
                selectedPublishWorkoutID = nil
            }
        ) {
            WorkoutPublishView(
                initialWorkoutID: selectedPublishWorkoutID
            )
        }
        .task(id: latestLoadKey) {
            await loadLatestDetail()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Activity Center")
                    .font(.system(size: 27, weight: .bold))

                Text("Your latest workout, presented at a glance.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer()

            NavigationLink {
                SocialHubView(initialTab: .feed)
            } label: {
                HStack(spacing: 5) {
                    Text("See all")
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var pendingRequests: some View {
        NavigationLink {
            SocialHubView(initialTab: .requests)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "bolt.badge.clock.fill")
                    .foregroundStyle(.orange)

                Text(
                    "\(social.pendingRequestCount) need\(social.pendingRequestCount == 1 ? "s" : "") your attention"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(
                Color.orange.opacity(0.08),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func workoutCard(
        _ workout: SocialPublishableWorkout
    ) -> some View {
        if workout.activity == .strength {
            let log = strengthWorkoutLog(for: workout)
            let summary =
                log.map {
                    StrengthMuscleProfileBuilder.make(
                        workout: $0,
                        library: exerciseLibrary.allExercises
                    )
                } ?? .empty

            NavigationLink {
                HomeActivityStrengthDetailView(
                    workout: workout,
                    strengthWorkout: log
                )
            } label: {
                HomeActivityStrengthCardV2(
                    workout: workout,
                    summary: summary,
                    isPublished: isPublished(workout)
                )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                publishMenu(workout)
                    .padding(14)
            }
        } else if workout.activity.isActivityCenterOutdoor {
            NavigationLink {
                HomeActivityRunDetailView(
                    workout: workout,
                    initialDetail:
                        detailWorkoutID == workout.id
                            ? detail
                            : nil,
                    initialAIInsight: nil
                )
            } label: {
                HomeActivityOutdoorCardV2(
                    workout: workout,
                    detail:
                        detailWorkoutID == workout.id
                            ? detail
                            : nil,
                    isPublished: isPublished(workout)
                )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                publishMenu(workout)
                    .padding(14)
            }
        } else {
            NavigationLink {
                WorkoutHistoryDetailView(
                    workout: workout
                )
            } label: {
                HomeActivityGenericCardV2(
                    workout: workout,
                    isPublished: isPublished(workout)
                )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                publishMenu(workout)
                    .padding(14)
            }
        }
    }

    private func publishMenu(
        _ workout: SocialPublishableWorkout
    ) -> some View {
        Menu {
            Button {
                selectedPublishWorkoutID = workout.id
                showingPublish = true
            } label: {
                Label(
                    isPublished(workout)
                        ? "Update post"
                        : "Post workout",
                    systemImage: "square.and.arrow.up"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .frame(width: 36, height: 36)
                .background(
                    Color.white.opacity(0.90),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.black.opacity(0.06),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workout actions")
    }

    private var emptyState: some View {
        HStack(spacing: 13) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 27))
                .foregroundStyle(ATHLTHTheme.vitality)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your activity starts here")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    "Complete a workout and ATHLTH will build the visual automatically."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer()
        }
        .padding(16)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
    }

    private func isPublished(
        _ workout: SocialPublishableWorkout
    ) -> Bool {
        social.feed.contains { item in
            item.actor.userID == social.currentUserID &&
            item.activity.kind == "workout" &&
            item.activity.metadata?["workout_id"] ==
                workout.id.uuidString
        }
    }

    private func strengthWorkoutLog(
        for workout: SocialPublishableWorkout
    ) -> StrengthWorkoutLog? {
        guard workout.activity == .strength else {
            return nil
        }

        return strength.workoutHistory.first {
            $0.id == workout.id ||
            $0.healthMetrics.healthKitWorkoutUUID ==
                workout.id
        }
    }

    @MainActor
    private func loadLatestDetail() async {
        detail = nil
        detailWorkoutID = nil

        guard let workout = latestWorkout,
              workout.activity.isActivityCenterOutdoor,
              health.workouts.contains(
                where: { $0.id == workout.id }
              )
        else {
            return
        }

        // Let Home paint before asking HealthKit for route samples.
        await Task.yield()

        guard !Task.isCancelled else {
            return
        }

        let loaded =
            await health.workoutDetail(
                for: workout.id
            )

        guard !Task.isCancelled else {
            return
        }

        detail = loaded
        detailWorkoutID = workout.id
    }
}

// MARK: - Outdoor card

private struct HomeActivityOutdoorCardV2: View {
    let workout: SocialPublishableWorkout
    let detail: WorkoutDetail?
    let isPublished: Bool

    private var routeLocations: [CLLocation] {
        HomeActivityRouteSanitizer.validLocations(
            detail?.route ?? []
        )
    }

    private var routeCoordinates:
        [CLLocationCoordinate2D] {
        HomeActivityRouteSanitizer.sampledCoordinates(
            from: routeLocations,
            maximumCount: 96
        )
    }

    private var elevationGainMeters: Double? {
        HomeActivityRouteMetrics.elevationGain(
            from: routeLocations
        )
    }

    private var highestAltitudeMeters: Double? {
        HomeActivityRouteMetrics.highestAltitude(
            in: routeLocations
        )
    }

    private var paceRange:
        HomeActivityPaceRange? {
        HomeActivityRouteMetrics.paceRange(
            from: routeLocations,
            fallbackAverage:
                averagePaceSecondsPerKilometer
        )
    }

    private var averagePaceSecondsPerKilometer:
        Double? {
        guard let distance =
                workout.distanceMeters,
              distance.isFinite,
              distance > 1,
              workout.duration.isFinite,
              workout.duration > 0
        else {
            return nil
        }

        let value =
            workout.duration /
            (distance / 1_000)

        guard value.isFinite,
              value >= 120,
              value <= 1_800
        else {
            return nil
        }

        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            workoutHeader

            routeHero

            summaryPanel

            intensityPanel
        }
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.075),
            radius: 14,
            x: 0,
            y: 7
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
    }

    private var workoutHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: workout.activity.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer(minLength: 46)

            if isPublished {
                Text("SHARED")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private var routeHero: some View {
        ZStack(alignment: .topLeading) {
            HomeActivityRoutePreviewV2(
                coordinates: routeCoordinates,
                highestAltitudeMeters:
                    highestAltitudeMeters
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    .clear,
                    Color.black.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack {
                Image(
                    systemName: "square.3.layers.3d"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .frame(width: 38, height: 38)
                .background(
                    .ultraThinMaterial,
                    in: Circle()
                )

                Spacer()

                if let highestAltitudeMeters,
                   highestAltitudeMeters > 0 {
                    HStack(spacing: 5) {
                        Image(
                            systemName: "mountain.2.fill"
                        )
                        Text(
                            "\(Int(highestAltitudeMeters.rounded())) m"
                        )
                    }
                    .font(
                        .caption.weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(
                        .ultraThinMaterial,
                        in: Capsule()
                    )
                }
            }
            .padding(13)
        }
        .frame(height: 260)
        .clipped()
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        activityTitle,
                        systemImage: workout.activity.icon
                    )
                    .font(
                        .caption.weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Text(distanceText)
                        .font(
                            .system(
                                size: 36,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }

                if let ascentText {
                    Text("▲ \(ascentText)")
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                        .padding(.bottom, 5)
                }

                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    metric(
                        value: durationText,
                        title: "Time"
                    )
                    metricDivider
                    metric(
                        value: paceText,
                        title: "/km"
                    )
                    metricDivider
                    metric(
                        value: heartRateText,
                        title: "Avg HR",
                        suffix: "bpm"
                    )
                    metricDivider
                    metric(
                        value: ascentMetricText,
                        title: "Elevation"
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {
                    metric(
                        value: durationText,
                        title: "Time"
                    )
                    metric(
                        value: paceText,
                        title: "Pace"
                    )
                    metric(
                        value: heartRateText,
                        title: "Avg HR",
                        suffix: "bpm"
                    )
                    metric(
                        value: ascentMetricText,
                        title: "Elevation"
                    )
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.98)
        )
    }

    private var intensityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    "Pace / intensity",
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Spacer()

                if let paceRange {
                    Text(
                        "\(paceText(paceRange.fast)) – \(paceText(paceRange.slow)) /km"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }

            LinearGradient(
                colors: [
                    Color(
                        red: 0.04,
                        green: 0.65,
                        blue: 0.56
                    ),
                    Color(
                        red: 0.32,
                        green: 0.79,
                        blue: 0.42
                    ),
                    Color(
                        red: 0.78,
                        green: 0.86,
                        blue: 0.24
                    ),
                    Color(
                        red: 0.99,
                        green: 0.66,
                        blue: 0.10
                    ),
                    Color(
                        red: 0.93,
                        green: 0.22,
                        blue: 0.22
                    )
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 10)
            .clipShape(Capsule())

            if let paceRange {
                HStack(alignment: .top) {
                    legendValue(
                        "Faster",
                        paceText(paceRange.fast)
                    )

                    Spacer()

                    legendValue(
                        "Average",
                        paceText(
                            paceRange.average
                        )
                    )

                    Spacer()

                    legendValue(
                        "Slower",
                        paceText(paceRange.slow),
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 16)
        .background(
            ATHLTHTheme.cardWarm.opacity(0.54)
        )
    }

    private func metric(
        value: String,
        title: String,
        suffix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: 3
            ) {
                Text(value)
                    .font(
                        .system(
                            size: 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let suffix {
                    Text(suffix)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 7)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.075))
            .frame(width: 1, height: 42)
    }

    private func legendValue(
        _ title: String,
        _ value: String,
        alignment: HorizontalAlignment =
            .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            Text("\(value) /km")
                .font(
                    .caption2.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }
    }

    private var activityTitle: String {
        switch workout.activity {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .cycling:
            return "Cycling"
        case .hiking:
            return "Hiking"
        default:
            return workout.activity.rawValue
        }
    }

    private var distanceText: String {
        guard let distance =
                workout.distanceMeters,
              distance.isFinite,
              distance > 0
        else {
            return "—"
        }

        return String(
            format: "%.2f km",
            distance / 1_000
        )
    }

    private var durationText: String {
        HomeActivityRouteMetrics.durationText(
            workout.duration
        )
    }

    private var paceText: String {
        guard let pace =
                averagePaceSecondsPerKilometer
        else {
            return "—"
        }

        return paceText(pace)
    }

    private func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        HomeActivityRouteMetrics.paceText(
            secondsPerKilometer
        )
    }

    private var heartRateText: String {
        guard let value =
                detail?.averageHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return String(
            format: "%.0f",
            value
        )
    }

    private var ascentText: String? {
        guard let elevationGainMeters,
              elevationGainMeters > 0
        else {
            return nil
        }

        return String(
            format: "%.0f m",
            elevationGainMeters
        )
    }

    private var ascentMetricText: String {
        ascentText ?? "—"
    }
}

// MARK: - Strength card

private struct HomeActivityStrengthCardV2: View {
    let workout: SocialPublishableWorkout
    let summary: StrengthMuscleSessionSummary
    let isPublished: Bool

    private var topMuscles:
        [StrengthMuscleActivation] {
        Array(
            summary.profile
                .topActivations
                .prefix(4)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        Color.indigo.opacity(0.09),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Strength")
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        workout.startDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer(minLength: 46)

                if isPublished {
                    Text("SHARED")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            ATHLTHTheme.champagneSoft,
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.95,
                            green: 0.95,
                            blue: 0.98
                        ),
                        Color.white,
                        ATHLTHTheme.cardWarm
                            .opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                StrengthMuscleMapView(
                    profile: summary.profile,
                    compact: true
                )
                .padding(.vertical, 18)
                .padding(.horizontal, 58)
            }
            .frame(height: 250)
            .clipped()

            VStack(alignment: .leading, spacing: 13) {
                Text(displayTitle)
                    .font(
                        .system(
                            size: 25,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                HStack(spacing: 0) {
                    strengthMetric(
                        HomeActivityRouteMetrics.durationText(
                            workout.duration
                        ),
                        "Time"
                    )
                    metricDivider
                    strengthMetric(
                        "\(summary.exercises.count)",
                        "Exercises"
                    )
                    metricDivider
                    strengthMetric(
                        "\(summary.totalSets)",
                        "Sets"
                    )
                    metricDivider
                    strengthMetric(
                        volumeText,
                        "Volume"
                    )
                }

                if !topMuscles.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(topMuscles) {
                            activation in

                            Text(
                                activation.region.title
                            )
                            .font(
                                .caption2.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Color.indigo.opacity(0.07),
                                in: Capsule()
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.075),
            radius: 14,
            x: 0,
            y: 7
        )
    }

    private var displayTitle: String {
        let trimmed =
            workout.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !trimmed.isEmpty,
           trimmed.lowercased() != "strength" {
            return trimmed
        }

        return "Strength session"
    }

    private var volumeText: String {
        guard summary.totalVolumeKilograms > 0
        else {
            return "—"
        }

        if summary.totalVolumeKilograms >= 1_000 {
            return String(
                format: "%.1f t",
                summary.totalVolumeKilograms /
                    1_000
            )
        }

        return String(
            format: "%.0f kg",
            summary.totalVolumeKilograms
        )
    }

    private func strengthMetric(
        _ value: String,
        _ title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(
                    .system(
                        size: 16,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 7)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.075))
            .frame(width: 1, height: 40)
    }
}

// MARK: - Generic card

private struct HomeActivityGenericCardV2: View {
    let workout: SocialPublishableWorkout
    let isPublished: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.activity.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(width: 52, height: 52)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.activity.rawValue)
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Text(workout.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 42)

            if isPublished {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }
        }
        .padding(16)
        .background(
            Color.white,
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Crash-safe route preview

enum HomeActivityRouteSanitizer {
    static func validLocations(
        _ locations: [CLLocation]
    ) -> [CLLocation] {
        locations.filter {
            isValid($0.coordinate)
        }
    }

    static func sampledCoordinates(
        from locations: [CLLocation],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        sampled(
            validLocations(locations)
                .map(\.coordinate),
            maximumCount: maximumCount
        )
    }

    static func sampled(
        _ coordinates:
            [CLLocationCoordinate2D],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        let valid =
            coordinates.filter(isValid)

        guard maximumCount > 1,
              valid.count > maximumCount
        else {
            return valid
        }

        let lastIndex = valid.count - 1
        let step =
            Double(lastIndex) /
            Double(maximumCount - 1)

        return (0..<maximumCount).map {
            index in

            valid[
                min(
                    Int(
                        (
                            Double(index) *
                            step
                        )
                        .rounded()
                    ),
                    lastIndex
                )
            ]
        }
    }

    static func isValid(
        _ coordinate:
            CLLocationCoordinate2D
    ) -> Bool {
        coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        CLLocationCoordinate2DIsValid(
            coordinate
        )
    }
}

private struct HomeActivityRoutePreviewV2: View {
    let coordinates:
        [CLLocationCoordinate2D]
    let highestAltitudeMeters: Double?

    @State private var image: UIImage?

    private var safeCoordinates:
        [CLLocationCoordinate2D] {
        HomeActivityRouteSanitizer.sampled(
            coordinates,
            maximumCount: 96
        )
    }

    private var cacheKey: String {
        HomeActivityRouteSnapshotRendererV2
            .cacheKey(
                coordinates:
                    safeCoordinates
            )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(
                        red: 0.83,
                        green: 0.89,
                        blue: 0.82
                    ),
                    Color(
                        red: 0.88,
                        green: 0.86,
                        blue: 0.72
                    ),
                    Color(
                        red: 0.72,
                        green: 0.83,
                        blue: 0.86
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if safeCoordinates.count >= 2 {
                ProgressView()
                    .tint(
                        ATHLTHTheme.primaryText
                    )
            } else {
                VStack(spacing: 10) {
                    Image(
                        systemName:
                            "mountain.2.fill"
                    )
                    .font(
                        .system(
                            size: 58,
                            weight: .light
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                            .opacity(0.48)
                    )

                    Text("Route appears when GPS data is available")
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }
        }
        .task(id: cacheKey) {
            image = nil

            guard safeCoordinates.count >= 2
            else {
                return
            }

            let rendered =
                await HomeActivityRouteSnapshotRendererV2
                    .shared
                    .image(
                        coordinates:
                            safeCoordinates
                    )

            guard !Task.isCancelled else {
                return
            }

            image = rendered
        }
    }
}

@MainActor
private final class
    HomeActivityRouteSnapshotRendererV2 {
    static let shared =
        HomeActivityRouteSnapshotRendererV2()

    private let cache =
        NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 4
        cache.totalCostLimit =
            8 * 1_024 * 1_024
    }

    static func cacheKey(
        coordinates:
            [CLLocationCoordinate2D]
    ) -> String {
        let sampled =
            HomeActivityRouteSanitizer.sampled(
                coordinates,
                maximumCount: 12
            )

        guard !sampled.isEmpty else {
            return "activity-v2-empty"
        }

        return "activity-v2|" +
            sampled.map {
                String(
                    format: "%.4f,%.4f",
                    $0.latitude,
                    $0.longitude
                )
            }
            .joined(separator: "|")
    }

    func image(
        coordinates:
            [CLLocationCoordinate2D]
    ) async -> UIImage? {
        let points =
            HomeActivityRouteSanitizer.sampled(
                coordinates,
                maximumCount: 96
            )

        guard points.count >= 2,
              !Task.isCancelled
        else {
            return nil
        }

        let key =
            Self.cacheKey(
                coordinates: points
            ) as NSString

        if let cached =
            cache.object(forKey: key) {
            return cached
        }

        let size =
            CGSize(
                width: 420,
                height: 260
            )

        let options =
            MKMapSnapshotter.Options()
        options.size = size
        options.scale = 1.5
        options.region =
            Self.safeRegion(
                for: points
            )
        options.traitCollection =
            UITraitCollection(
                userInterfaceStyle: .light
            )

        // Hybrid imagery keeps the terrain character from the reference,
        // but deliberately avoids realistic 3D elevation on Home.
        let configuration =
            MKHybridMapConfiguration(
                elevationStyle: .flat
            )
        configuration.showsTraffic = false
        options.preferredConfiguration =
            configuration

        do {
            let snapshot =
                try await MKMapSnapshotter(
                    options: options
                )
                .start()

            guard !Task.isCancelled else {
                return nil
            }

            let format =
                UIGraphicsImageRendererFormat
                    .default()
            format.scale = 1.5
            format.opaque = true

            let renderer =
                UIGraphicsImageRenderer(
                    size: size,
                    format: format
                )

            let rendered =
                renderer.image { context in
                    snapshot.image.draw(
                        in: CGRect(
                            origin: .zero,
                            size: size
                        )
                    )

                    let overlay =
                        UIColor.white
                            .withAlphaComponent(
                                0.08
                            )
                    overlay.setFill()
                    context.fill(
                        CGRect(
                            origin: .zero,
                            size: size
                        )
                    )

                    Self.drawRoute(
                        points,
                        on: snapshot
                    )
                }

            guard !Task.isCancelled else {
                return nil
            }

            let cost =
                Int(
                    rendered.size.width *
                    rendered.size.height *
                    rendered.scale *
                    rendered.scale *
                    4
                )

            cache.setObject(
                rendered,
                forKey: key,
                cost: cost
            )

            return rendered
        } catch {
            return nil
        }
    }

    private static func safeRegion(
        for points:
            [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let first = points.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 63.4305,
                        longitude: 10.3951
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.08,
                        longitudeDelta: 0.08
                    )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for point in points.dropFirst() {
            minLatitude =
                min(
                    minLatitude,
                    point.latitude
                )
            maxLatitude =
                max(
                    maxLatitude,
                    point.latitude
                )
            minLongitude =
                min(
                    minLongitude,
                    point.longitude
                )
            maxLongitude =
                max(
                    maxLongitude,
                    point.longitude
                )
        }

        let center =
            CLLocationCoordinate2D(
                latitude:
                    (minLatitude +
                     maxLatitude) / 2,
                longitude:
                    (minLongitude +
                     maxLongitude) / 2
            )

        let latitudeDelta =
            min(
                max(
                    (
                        maxLatitude -
                        minLatitude
                    ) * 1.55,
                    0.008
                ),
                90
            )

        let longitudeDelta =
            min(
                max(
                    (
                        maxLongitude -
                        minLongitude
                    ) * 1.55,
                    0.008
                ),
                180
            )

        return MKCoordinateRegion(
            center: center,
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        latitudeDelta,
                    longitudeDelta:
                        longitudeDelta
                )
        )
    }

    private static func drawRoute(
        _ points:
            [CLLocationCoordinate2D],
        on snapshot:
            MKMapSnapshotter.Snapshot
    ) {
        let renderedPoints =
            points.map {
                snapshot.point(for: $0)
            }

        guard renderedPoints.count >= 2
        else {
            return
        }

        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for (
            index,
            point
        ) in renderedPoints.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        UIColor.black
            .withAlphaComponent(0.20)
            .setStroke()
        path.lineWidth = 15
        path.stroke()

        UIColor.white
            .withAlphaComponent(0.96)
            .setStroke()
        path.lineWidth = 12
        path.stroke()

        let palette: [UIColor] = [
            UIColor(
                red: 0.02,
                green: 0.64,
                blue: 0.53,
                alpha: 1
            ),
            UIColor(
                red: 0.22,
                green: 0.78,
                blue: 0.40,
                alpha: 1
            ),
            UIColor(
                red: 0.78,
                green: 0.86,
                blue: 0.20,
                alpha: 1
            ),
            UIColor(
                red: 0.99,
                green: 0.62,
                blue: 0.08,
                alpha: 1
            ),
            UIColor(
                red: 0.94,
                green: 0.24,
                blue: 0.19,
                alpha: 1
            )
        ]

        for index in
            1..<renderedPoints.count {
            let progress =
                CGFloat(index - 1) /
                CGFloat(
                    max(
                        renderedPoints.count -
                            2,
                        1
                    )
                )

            let color =
                interpolatedColor(
                    palette: palette,
                    progress: progress
                )

            let segment =
                UIBezierPath()
            segment.move(
                to: renderedPoints[
                    index - 1
                ]
            )
            segment.addLine(
                to: renderedPoints[index]
            )
            segment.lineCapStyle = .round
            color.setStroke()
            segment.lineWidth = 8
            segment.stroke()
        }

        drawStart(
            renderedPoints.first
        )
        drawFinish(
            renderedPoints.last
        )
    }

    private static func drawStart(
        _ point: CGPoint?
    ) {
        guard let point else {
            return
        }

        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 8,
                y: point.y - 8,
                width: 16,
                height: 16
            )
        )
        .fill()

        UIColor(
            red: 0.02,
            green: 0.64,
            blue: 0.53,
            alpha: 1
        )
        .setFill()

        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 4.5,
                y: point.y - 4.5,
                width: 9,
                height: 9
            )
        )
        .fill()
    }

    private static func drawFinish(
        _ point: CGPoint?
    ) {
        guard let point else {
            return
        }

        UIColor.white.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 8,
                y: point.y - 8,
                width: 16,
                height: 16
            )
        )
        .fill()

        UIColor.black
            .withAlphaComponent(0.90)
            .setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: point.x - 5,
                y: point.y - 5,
                width: 10,
                height: 10
            )
        )
        .fill()
    }

    private static func interpolatedColor(
        palette: [UIColor],
        progress: CGFloat
    ) -> UIColor {
        guard palette.count > 1 else {
            return palette.first ??
                .systemGreen
        }

        let clamped =
            min(max(progress, 0), 1)
        let scaled =
            clamped *
            CGFloat(
                palette.count - 1
            )
        let lower =
            min(
                Int(floor(scaled)),
                palette.count - 1
            )
        let upper =
            min(
                lower + 1,
                palette.count - 1
            )
        let fraction =
            scaled -
            CGFloat(lower)

        return interpolate(
            palette[lower],
            palette[upper],
            fraction: fraction
        )
    }

    private static func interpolate(
        _ from: UIColor,
        _ to: UIColor,
        fraction: CGFloat
    ) -> UIColor {
        let t =
            min(max(fraction, 0), 1)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        var tr: CGFloat = 0
        var tg: CGFloat = 0
        var tb: CGFloat = 0
        var ta: CGFloat = 0

        guard from.getRed(
                &fr,
                green: &fg,
                blue: &fb,
                alpha: &fa
              ),
              to.getRed(
                &tr,
                green: &tg,
                blue: &tb,
                alpha: &ta
              )
        else {
            return from
        }

        return UIColor(
            red:
                fr + (tr - fr) * t,
            green:
                fg + (tg - fg) * t,
            blue:
                fb + (tb - fb) * t,
            alpha:
                fa + (ta - fa) * t
        )
    }
}

// MARK: - Metrics

private struct HomeActivityPaceRange {
    let fast: Double
    let average: Double
    let slow: Double
}

private enum HomeActivityRouteMetrics {
    static func durationText(
        _ duration: TimeInterval
    ) -> String {
        guard duration.isFinite,
              duration > 0
        else {
            return "—"
        }

        let totalSeconds =
            max(
                Int(duration.rounded()),
                0
            )
        let hours =
            totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600) / 60
        let seconds =
            totalSeconds % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }

    static func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        guard secondsPerKilometer
                .isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let seconds =
            max(
                Int(
                    secondsPerKilometer
                        .rounded()
                ),
                0
            )

        return String(
            format:
                "%d:%02d",
            seconds / 60,
            seconds % 60
        )
    }

    static func elevationGain(
        from locations: [CLLocation]
    ) -> Double? {
        guard locations.count >= 2 else {
            return nil
        }

        var gain = 0.0

        for index in
            1..<locations.count {
            let previous =
                locations[index - 1]
            let current =
                locations[index]

            guard previous.altitude.isFinite,
                  current.altitude.isFinite
            else {
                continue
            }

            let delta =
                current.altitude -
                previous.altitude

            // Ignore obvious GPS altitude spikes in a Home summary.
            if delta > 0,
               delta < 120 {
                gain += delta
            }
        }

        return gain > 0
            ? gain
            : nil
    }

    static func highestAltitude(
        in locations: [CLLocation]
    ) -> Double? {
        locations
            .map(\.altitude)
            .filter {
                $0.isFinite &&
                $0 > -500 &&
                $0 < 9_500
            }
            .max()
    }

    static func paceRange(
        from locations: [CLLocation],
        fallbackAverage: Double?
    ) -> HomeActivityPaceRange? {
        var paces: [Double] = []

        if locations.count >= 2 {
            for index in
                1..<locations.count {
                let previous =
                    locations[index - 1]
                let current =
                    locations[index]

                let seconds =
                    current.timestamp
                        .timeIntervalSince(
                            previous.timestamp
                        )
                let meters =
                    current.distance(
                        from: previous
                    )

                guard seconds.isFinite,
                      meters.isFinite,
                      seconds > 1,
                      meters >= 5
                else {
                    continue
                }

                let pace =
                    seconds /
                    (meters / 1_000)

                if pace.isFinite,
                   pace >= 120,
                   pace <= 1_200 {
                    paces.append(pace)
                }
            }
        }

        if paces.count >= 4 {
            let sorted =
                paces.sorted()

            let fastIndex =
                min(
                    Int(
                        Double(
                            sorted.count - 1
                        ) * 0.15
                    ),
                    sorted.count - 1
                )
            let slowIndex =
                min(
                    Int(
                        Double(
                            sorted.count - 1
                        ) * 0.85
                    ),
                    sorted.count - 1
                )

            let average =
                sorted.reduce(
                    0,
                    +
                ) /
                Double(sorted.count)

            return HomeActivityPaceRange(
                fast: sorted[fastIndex],
                average: average,
                slow: sorted[slowIndex]
            )
        }

        guard let fallbackAverage,
              fallbackAverage.isFinite,
              fallbackAverage > 0
        else {
            return nil
        }

        return HomeActivityPaceRange(
            fast:
                max(
                    fallbackAverage * 0.84,
                    120
                ),
            average: fallbackAverage,
            slow:
                min(
                    fallbackAverage * 1.18,
                    1_200
                )
        )
    }
}

private extension WorkoutActivity {
    var isActivityCenterOutdoor: Bool {
        switch self {
        case .running,
             .walking,
             .cycling,
             .hiking:
            return true
        default:
            return false
        }
    }
}
