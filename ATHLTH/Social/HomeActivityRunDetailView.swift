import CoreLocation
import MapKit
import SwiftUI

struct HomeActivityRunDetailView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore

    let workout: SocialPublishableWorkout

    @State private var detail: WorkoutDetail?
    @State private var aiInsight: WorkoutAIInsight?
    @State private var isLoadingDetail = false
    @State private var isLoadingAIInsight = false

    init(
        workout: SocialPublishableWorkout,
        initialDetail: WorkoutDetail?,
        initialAIInsight: WorkoutAIInsight?
    ) {
        self.workout = workout
        _detail = State(
            initialValue: initialDetail
        )
        _aiInsight = State(
            initialValue: initialAIInsight
        )
    }

    private var route: [CLLocation] {
        let source = detail?.route ?? []
        let accurate =
            source
                .filter {
                    $0.coordinate.latitude.isFinite &&
                    $0.coordinate.longitude.isFinite &&
                    (
                        $0.horizontalAccuracy < 0 ||
                        $0.horizontalAccuracy <= 65
                    )
                }
                .sorted {
                    $0.timestamp < $1.timestamp
                }

        if accurate.count >= 2 {
            return accurate
        }

        return source
            .filter {
                $0.coordinate.latitude.isFinite &&
                $0.coordinate.longitude.isFinite
            }
            .sorted {
                $0.timestamp < $1.timestamp
            }
    }

    private var routeCoordinates:
        [CLLocationCoordinate2D] {
        route.map(\.coordinate)
    }

    private var paceSegments:
        [HomeActivityPaceSegment] {
        HomeActivityPaceSegmentBuilder.make(
            from: route
        )
    }

    private var paceBounds:
        (fast: Double, slow: Double) {
        let values =
            paceSegments
                .map(
                    \.paceSecondsPerKilometer
                )
                .filter(\.isFinite)
                .sorted()

        guard values.count >= 2 else {
            let fallback =
                values.first ??
                averagePaceSeconds ??
                360
            return (
                max(fallback * 0.92, 1),
                fallback * 1.08
            )
        }

        let last = values.count - 1
        let fastIndex =
            min(
                max(
                    Int(
                        (
                            Double(last) *
                            0.15
                        )
                        .rounded()
                    ),
                    0
                ),
                last
            )
        let slowIndex =
            min(
                max(
                    Int(
                        (
                            Double(last) *
                            0.85
                        )
                        .rounded()
                    ),
                    0
                ),
                last
            )

        let fast = values[fastIndex]
        let slow =
            max(
                values[slowIndex],
                fast + 1
            )

        return (fast, slow)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard

                mapCard

                routeFactsCard

                coachCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(
            detailNavigationTitle
        )
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.id) {
            await loadDetailAndCoach()
        }
    }

    private var summaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(
                alignment: .firstTextBaseline
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Label(
                        activityTitle,
                        systemImage:
                            workout.activity.icon
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
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

                Spacer()

                if let ascentText {
                    Label(
                        ascentText,
                        systemImage:
                            "mountain.2.fill"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }
            }

            HStack(
                alignment: .lastTextBaseline,
                spacing: 6
            ) {
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

                if distanceText != "—" {
                    Text("completed")
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }

            ViewThatFits(
                in: .horizontal
            ) {
                HStack(spacing: 0) {
                    summaryMetric(
                        "Time",
                        durationText
                    )
                    summaryDivider
                    summaryMetric(
                        "Avg. pace",
                        paceText
                    )
                    summaryDivider
                    summaryMetric(
                        "Avg. HR",
                        averageHeartRateText
                    )
                    summaryDivider
                    summaryMetric(
                        "Max HR",
                        maxHeartRateText
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {
                    summaryMetric(
                        "Time",
                        durationText
                    )
                    summaryMetric(
                        "Avg. pace",
                        paceText
                    )
                    summaryMetric(
                        "Avg. HR",
                        averageHeartRateText
                    )
                    summaryMetric(
                        "Max HR",
                        maxHeartRateText
                    )
                }
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private var mapCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text("Route")
                        .font(
                            .headline.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        "Apple Maps · pace by segment"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                if isLoadingDetail {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if routeCoordinates.count >= 2 {
                Map(
                    initialPosition: .region(
                        routeRegion
                    )
                ) {
                    MapPolyline(
                        coordinates:
                            routeCoordinates
                    )
                    .stroke(
                        Color.white
                            .opacity(0.92),
                        lineWidth: 11
                    )

                    if paceSegments.isEmpty {
                        MapPolyline(
                            coordinates:
                                routeCoordinates
                        )
                        .stroke(
                            ATHLTHTheme.vitality,
                            lineWidth: 7
                        )
                    } else {
                        ForEach(
                            paceSegments
                        ) { segment in
                            MapPolyline(
                                coordinates:
                                    segment
                                        .coordinates
                            )
                            .stroke(
                                paceColor(
                                    segment
                                        .paceSecondsPerKilometer
                                ),
                                lineWidth: 7
                            )
                        }
                    }

                    if let first =
                        routeCoordinates.first {
                        Marker(
                            "Start",
                            coordinate: first
                        )
                        .tint(
                            HomeActivityPaceScale
                                .fast
                        )
                    }

                    if let last =
                        routeCoordinates.last {
                        Marker(
                            "Finish",
                            coordinate: last
                        )
                        .tint(.black)
                    }
                }
                .frame(height: 350)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .stroke(
                        Color.white
                            .opacity(0.8),
                        lineWidth: 0.8
                    )
                }

                paceLegend
            } else {
                ContentUnavailableView(
                    "No GPS route",
                    systemImage: "map",
                    description: Text(
                        "Route details appear when this workout contains GPS data."
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 220
                )
                .background(
                    ATHLTHTheme.surfaceStone,
                    in: RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
            }
        }
        .padding(14)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    private var paceLegend: some View {
        VStack(spacing: 7) {
            LinearGradient(
                colors:
                    HomeActivityPaceScale
                        .legendColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 7)
            .clipShape(Capsule())

            HStack {
                Text("Faster")
                Spacer()
                Text("Average")
                Spacer()
                Text("Slower")
            }
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            Text(
                "Colors are relative to this workout."
            )
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
                    .opacity(0.78)
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(.horizontal, 2)
    }

    private var routeFactsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text("Route details")
                .font(
                    .headline.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 10
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 10
                    )
                ],
                spacing: 10
            ) {
                routeFact(
                    icon: "mountain.2.fill",
                    label: "Elevation gain",
                    value:
                        ascentText ??
                        "—"
                )

                routeFact(
                    icon:
                        "arrow.up.right.circle.fill",
                    label: "Highest point",
                    value:
                        highestPointText
                )

                routeFact(
                    icon: "flame.fill",
                    label: "Active energy",
                    value:
                        activeEnergyText
                )

                routeFact(
                    icon:
                        runningPowerText == "—"
                            ? "heart.fill"
                            : "bolt.fill",
                    label:
                        runningPowerText == "—"
                            ? "Max heart rate"
                            : "Avg. power",
                    value:
                        runningPowerText == "—"
                            ? maxHeartRateText
                            : runningPowerText
                )
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    private var coachCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 8) {
                Label(
                    "ATHLTH COACH",
                    systemImage: "sparkles"
                )
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(.indigo)

                Text("ATHLTH+")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(
                        .horizontal,
                        6
                    )
                    .padding(
                        .vertical,
                        3
                    )
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )

                Spacer()

                if isLoadingAIInsight {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let aiInsight {
                Text(aiInsight.headline)
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(aiInsight.summary)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            } else if isLoadingAIInsight {
                Text(
                    "Coach is analyzing pace, route, elevation and effort…"
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            } else {
                Text(coachUnavailableText)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.indigo
                        .opacity(0.07),
                    ATHLTHTheme.card
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.indigo
                    .opacity(0.10),
                lineWidth: 1
            )
        }
    }

    @MainActor
    private func loadDetailAndCoach() async {
        if detail == nil {
            isLoadingDetail = true
            detail =
                await health.workoutDetail(
                    for: workout.id
                )
            isLoadingDetail = false
        }

        await loadCoachInsightIfNeeded()
    }

    @MainActor
    private func loadCoachInsightIfNeeded() async {
        guard aiInsight == nil,
              session.hasPaidAccess,
              session.aiHealthDataSharingEnabled,
              let summary =
                health.workouts.first(
                    where: {
                        $0.id == workout.id
                    }
                )
        else {
            return
        }

        isLoadingAIInsight = true
        defer {
            isLoadingAIInsight = false
        }

        let context =
            await health.workoutAIInsightContext(
                for: summary,
                detail: detail,
                maximumHeartRateBPM:
                    session
                        .onboardingProfile?
                        .maximumHeartRateBPM
            )

        do {
            aiInsight =
                try await WorkoutInsightAIService()
                    .generate(
                        workoutID: workout.id,
                        context: context
                    )
        } catch {
            // Keep the detail page useful even when Coach is temporarily unavailable.
        }
    }

    private func summaryMetric(
        _ label: String,
        _ value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)

            Text(value)
                .font(
                    .caption.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 8)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider
            )
            .frame(
                width: 1,
                height: 34
            )
    }

    private func routeFact(
        icon: String,
        label: String,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(
                    width: 34,
                    height: 34
                )
                .background(
                    ATHLTHTheme
                        .surfaceSage,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)

                Text(value)
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.75
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            ATHLTHTheme.surfaceStone
                .opacity(0.62),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private func paceColor(
        _ pace: Double
    ) -> Color {
        HomeActivityPaceScale.color(
            pace:
                pace,
            fast:
                paceBounds.fast,
            slow:
                paceBounds.slow
        )
    }

    private var routeRegion:
        MKCoordinateRegion {
        guard let first =
                routeCoordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.05,
                        longitudeDelta: 0.05
                    )
            )
        }

        var minLatitude =
            first.latitude
        var maxLatitude =
            first.latitude
        var minLongitude =
            first.longitude
        var maxLongitude =
            first.longitude

        for coordinate in
            routeCoordinates.dropFirst() {
            minLatitude =
                min(
                    minLatitude,
                    coordinate.latitude
                )
            maxLatitude =
                max(
                    maxLatitude,
                    coordinate.latitude
                )
            minLongitude =
                min(
                    minLongitude,
                    coordinate.longitude
                )
            maxLongitude =
                max(
                    maxLongitude,
                    coordinate.longitude
                )
        }

        let latitudeDelta =
            max(
                (
                    maxLatitude -
                    minLatitude
                ) * 1.35,
                0.006
            )
        let longitudeDelta =
            max(
                (
                    maxLongitude -
                    minLongitude
                ) * 1.35,
                0.006
            )

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (
                            minLatitude +
                            maxLatitude
                        ) / 2,
                    longitude:
                        (
                            minLongitude +
                            maxLongitude
                        ) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        latitudeDelta,
                    longitudeDelta:
                        longitudeDelta
                )
        )
    }

    private var elevationGainMeters: Double {
        guard route.count >= 2 else {
            return 0
        }

        var gain = 0.0

        for index in 1..<route.count {
            let delta =
                route[index].altitude -
                route[index - 1].altitude

            if delta > 0,
               delta < 50 {
                gain += delta
            }
        }

        return gain
    }

    private var highestAltitudeMeters: Double? {
        route
            .map(\.altitude)
            .filter(\.isFinite)
            .max()
    }

    private var averagePaceSeconds: Double? {
        guard let distance =
                workout.distanceMeters,
              distance > 0
        else {
            return nil
        }

        let value =
            workout.duration /
            (distance / 1_000)

        return value.isFinite &&
            value > 0
            ? value
            : nil
    }

    private var detailNavigationTitle: String {
        switch workout.activity {
        case .running:
            return "Run details"
        case .walking:
            return "Walk details"
        case .cycling:
            return "Ride details"
        case .hiking:
            return "Hike details"
        default:
            return "Workout details"
        }
    }

    private var activityTitle: String {
        switch workout.activity {
        case .running:
            return "Run"
        case .walking:
            return "Walk"
        case .cycling:
            return "Ride"
        case .hiking:
            return "Hike"
        default:
            return workout.activity.rawValue
        }
    }

    private var distanceText: String {
        guard let distance =
                workout.distanceMeters,
              distance > 0
        else {
            return "—"
        }

        return String(
            format:
                "%.2f km",
            distance / 1_000
        )
    }

    private var durationText: String {
        let total =
            max(
                Int(
                    workout.duration
                        .rounded()
                ),
                0
            )
        let hours =
            total / 3_600
        let minutes =
            (total % 3_600) / 60
        let seconds =
            total % 60

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
            format:
                "%d:%02d",
            minutes,
            seconds
        )
    }

    private var paceText: String {
        guard let pace =
                averagePaceSeconds
        else {
            return "—"
        }

        return Self.paceText(
            pace
        )
    }

    private var averageHeartRateText: String {
        guard let value =
                detail?
                    .averageHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return "\(Int(value.rounded())) bpm"
    }

    private var maxHeartRateText: String {
        guard let value =
                detail?.maxHeartRate,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return "\(Int(value.rounded())) bpm"
    }

    private var ascentText: String? {
        guard elevationGainMeters >= 5
        else {
            return nil
        }

        return
            "\(Int(elevationGainMeters.rounded())) m"
    }

    private var highestPointText: String {
        guard let value =
                highestAltitudeMeters,
              value.isFinite
        else {
            return "—"
        }

        return "\(Int(value.rounded())) m"
    }

    private var activeEnergyText: String {
        guard let value =
                workout
                    .activeEnergyKilocalories,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return
            "\(Int(value.rounded())) kcal"
    }

    private var runningPowerText: String {
        guard let value =
                detail?
                    .averageRunningPowerWatts,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return
            "\(Int(value.rounded())) W"
    }

    private var coachUnavailableText: String {
        if !session.hasPaidAccess {
            return
                "Coach insight is available with ATHLTH+."
        }

        if !session
            .aiHealthDataSharingEnabled {
            return
                "Enable Coach health-data sharing in Settings to analyze this workout."
        }

        return
            "Coach insight is not available for this workout yet."
    }

    private static func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        guard secondsPerKilometer
            .isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let rounded =
            Int(
                secondsPerKilometer
                    .rounded()
            )
        let minutes =
            rounded / 60
        let seconds =
            rounded % 60

        return String(
            format:
                "%d:%02d /km",
            minutes,
            seconds
        )
    }
}

private struct HomeActivityPaceSegment:
    Identifiable {
    let id: Int
    let coordinates:
        [CLLocationCoordinate2D]
    let paceSecondsPerKilometer:
        Double
}

private enum HomeActivityPaceSegmentBuilder {
    static func make(
        from route: [CLLocation]
    ) -> [HomeActivityPaceSegment] {
        guard route.count >= 2 else {
            return []
        }

        var segments:
            [HomeActivityPaceSegment] = []
        var bucketCoordinates:
            [CLLocationCoordinate2D] = [
                route[0].coordinate
            ]
        var bucketDistance = 0.0
        var bucketDuration = 0.0
        var previous = route[0]

        func appendBucket(
            endingAt location: CLLocation
        ) {
            guard
                bucketCoordinates.count >= 2,
                bucketDistance >= 15,
                bucketDuration > 0
            else {
                return
            }

            let pace =
                bucketDuration /
                (bucketDistance / 1_000)

            guard pace.isFinite,
                  pace >= 25,
                  pace <= 2_400
            else {
                return
            }

            segments.append(
                HomeActivityPaceSegment(
                    id: segments.count,
                    coordinates:
                        bucketCoordinates,
                    paceSecondsPerKilometer:
                        pace
                )
            )
        }

        for current in route.dropFirst() {
            let elapsed =
                current.timestamp
                    .timeIntervalSince(
                        previous.timestamp
                    )
            let distance =
                current.distance(
                    from: previous
                )

            let valid =
                elapsed > 0 &&
                elapsed <= 120 &&
                distance >= 0 &&
                (
                    distance /
                    elapsed
                ) <= 12.5

            if valid {
                bucketCoordinates.append(
                    current.coordinate
                )
                bucketDistance +=
                    distance
                bucketDuration +=
                    elapsed

                if bucketDistance >= 70 ||
                    bucketDuration >= 24 {
                    appendBucket(
                        endingAt: current
                    )

                    bucketCoordinates = [
                        current.coordinate
                    ]
                    bucketDistance = 0
                    bucketDuration = 0
                }
            } else {
                if bucketDistance >= 15 {
                    appendBucket(
                        endingAt: previous
                    )
                }

                bucketCoordinates = [
                    current.coordinate
                ]
                bucketDistance = 0
                bucketDuration = 0
            }

            previous = current
        }

        if bucketDistance >= 15 {
            appendBucket(
                endingAt: previous
            )
        }

        return segments
    }
}

private enum HomeActivityPaceScale {
    static let fast =
        Color(
            red: 0.05,
            green: 0.62,
            blue: 0.49
        )

    static let legendColors: [Color] = [
        fast,
        Color(
            red: 0.19,
            green: 0.78,
            blue: 0.45
        ),
        Color(
            red: 0.68,
            green: 0.86,
            blue: 0.27
        ),
        Color(
            red: 0.96,
            green: 0.73,
            blue: 0.18
        ),
        Color(
            red: 0.96,
            green: 0.45,
            blue: 0.12
        )
    ]

    private static let rgb:
        [(Double, Double, Double)] = [
            (0.05, 0.62, 0.49),
            (0.19, 0.78, 0.45),
            (0.68, 0.86, 0.27),
            (0.96, 0.73, 0.18),
            (0.96, 0.45, 0.12)
        ]

    static func color(
        pace: Double,
        fast: Double,
        slow: Double
    ) -> Color {
        guard pace.isFinite,
              fast.isFinite,
              slow.isFinite,
              slow > fast
        else {
            return self.fast
        }

        let normalized =
            min(
                max(
                    (
                        pace -
                        fast
                    ) /
                    (
                        slow -
                        fast
                    ),
                    0
                ),
                1
            )
        let scaled =
            normalized *
            Double(rgb.count - 1)
        let lower =
            min(
                max(
                    Int(
                        floor(
                            scaled
                        )
                    ),
                    0
                ),
                rgb.count - 1
            )
        let upper =
            min(
                lower + 1,
                rgb.count - 1
            )
        let mix =
            scaled -
            Double(lower)

        let a = rgb[lower]
        let b = rgb[upper]

        return Color(
            red:
                a.0 +
                (
                    b.0 -
                    a.0
                ) *
                mix,
            green:
                a.1 +
                (
                    b.1 -
                    a.1
                ) *
                mix,
            blue:
                a.2 +
                (
                    b.2 -
                    a.2
                ) *
                mix
        )
    }
}
