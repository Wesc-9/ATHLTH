import CoreLocation
import MapKit
import SwiftUI

// MARK: - Personal activity surface used by Home

private enum HomePersonalActivityFilter:
    String,
    CaseIterable,
    Identifiable {
    case all
    case running
    case strength
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(
                english: "All",
                norwegian: "Alle"
            )
        case .running:
            return ATHLTHLocalization.choose(
                english: "Run",
                norwegian: "Løp"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .other:
            return ATHLTHLocalization.choose(
                english: "Other",
                norwegian: "Annet"
            )
        }
    }

    func includes(
        _ activity: WorkoutActivity
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .running:
            return activity == .running ||
                activity == .walking ||
                activity == .hiking
        case .strength:
            return activity == .strength
        case .other:
            return ![
                WorkoutActivity.running,
                .walking,
                .hiking,
                .strength
            ].contains(activity)
        }
    }
}

@MainActor
private enum HomePersonalWorkoutCatalog {
    static func merge(
        healthSummaries: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        phoneHistory: [PhoneWorkout]
    ) -> [SocialPublishableWorkout] {
        var byID: [UUID: SocialPublishableWorkout] = [:]

        for summary in healthSummaries {
            let workout =
                SocialPublishableWorkout(
                    summary: summary
                )
            byID[workout.id] = workout
        }

        // iPhone recordings enrich/restore ATHLTH-owned runs. The Health UUID
        // is reused when available, so this replaces rather than duplicates
        // the same workout.
        for phoneWorkout in phoneHistory
        where phoneWorkout.end != nil {
            let workout =
                SocialPublishableWorkout(
                    phoneWorkout:
                        phoneWorkout
                )
            byID[workout.id] = workout
        }

        // ATHLTH strength logs are intentionally applied last. They carry the
        // exercise names, sets, volume and muscle metadata that Apple Health
        // alone cannot reconstruct.
        for strengthWorkout in
            strengthHistory
            .filter({
                $0.isFinished
            }) {
            let workout =
                SocialPublishableWorkout(
                    strengthWorkout:
                        strengthWorkout
                )
            byID[workout.id] = workout
        }

        return byID.values.sorted {
            $0.startDate > $1.startDate
        }
    }

    static func strengthWorkout(
        for workout:
            SocialPublishableWorkout,
        in history:
            [StrengthWorkoutLog]
    ) -> StrengthWorkoutLog? {
        history.first {
            (
                $0.healthMetrics
                    .healthKitWorkoutUUID ??
                $0.id
            ) == workout.id
        }
    }

    static func phoneWorkout(
        for workout:
            SocialPublishableWorkout,
        in history:
            [PhoneWorkout]
    ) -> PhoneWorkout? {
        history.first {
            (
                $0.healthID ??
                $0.id
            ) == workout.id
        }
    }
}

struct HomePersonalRecentActivitySection:
    View {
    @EnvironmentObject private var health:
        HealthKitManager
    @EnvironmentObject private var strength:
        StrengthWorkoutStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    private var workouts:
        [SocialPublishableWorkout] {
        HomePersonalWorkoutCatalog.merge(
            healthSummaries:
                health.workouts,
            strengthHistory:
                strength.workoutHistory,
            phoneHistory:
                phoneWorkout.history
        )
    }

    private var latest:
        SocialPublishableWorkout? {
        workouts.first
    }

    private var recentSecondary:
        [SocialPublishableWorkout] {
        Array(
            workouts
                .dropFirst()
                .prefix(2)
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            header

            if let latest {
                NavigationLink {
                    HomePersonalActivityDestination(
                        workout: latest,
                        strengthWorkout:
                            strengthWorkout(
                                for: latest
                            )
                    )
                } label: {
                    HomePersonalFeaturedWorkoutCard(
                        workout: latest,
                        strengthWorkout:
                            strengthWorkout(
                                for: latest
                            ),
                        phoneWorkout:
                            localPhoneWorkout(
                                for: latest
                            )
                    )
                }
                .buttonStyle(.plain)

                if !recentSecondary.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: 145
                                ),
                                spacing: 10
                            )
                        ],
                        spacing: 10
                    ) {
                        ForEach(
                            recentSecondary
                        ) { workout in
                            NavigationLink {
                                HomePersonalActivityDestination(
                                    workout:
                                        workout,
                                    strengthWorkout:
                                        strengthWorkout(
                                            for:
                                                workout
                                        )
                                )
                            } label: {
                                HomePersonalCompactWorkoutCard(
                                    workout:
                                        workout,
                                    strengthWorkout:
                                        strengthWorkout(
                                            for:
                                                workout
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private var header: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: 12
        ) {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Recent activity",
                        norwegian:
                            "Siste aktivitet"
                    )
                )
                .font(
                    .headline.weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Your workouts from ATHLTH and Apple Health.",
                        norwegian:
                            "Dine økter fra ATHLTH og Apple Health."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            NavigationLink {
                HomePersonalActivityHistoryView()
            } label: {
                HStack(spacing: 5) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "See all",
                            norwegian: "Se alle"
                        )
                    )

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                }
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .padding(
                    .horizontal,
                    11
                )
                .frame(height: 32)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "figure.run.circle.fill"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 48,
                height: 48
            )
            .background(
                ATHLTHTheme.accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "No completed workouts yet",
                        norwegian:
                            "Ingen fullførte økter ennå"
                    )
                )
                .font(
                    .subheadline.weight(
                        .semibold
                    )
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Your own runs, strength sessions and other workouts will appear here.",
                        norwegian:
                            "Dine egne løpeøkter, styrkeøkter og andre økter vises her."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
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
                Color.black.opacity(
                    0.04
                ),
                lineWidth: 0.8
            )
        }
    }

    private func strengthWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> StrengthWorkoutLog? {
        HomePersonalWorkoutCatalog
            .strengthWorkout(
                for: workout,
                in:
                    strength
                        .workoutHistory
            )
    }

    private func localPhoneWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> PhoneWorkout? {
        HomePersonalWorkoutCatalog
            .phoneWorkout(
                for: workout,
                in:
                    phoneWorkout
                        .history
            )
    }
}

private struct HomePersonalFeaturedWorkoutCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomePersonalWorkoutVisual(
                workout: workout,
                strengthWorkout:
                    strengthWorkout,
                phoneWorkout:
                    phoneWorkout,
                exerciseLibrary:
                    exerciseLibrary,
                height: 154
            )

            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 8
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(workout.title)
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                        Text(
                            workout
                                .startDate
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Image(
                        systemName:
                            "arrow.up.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )
                }

                HStack(spacing: 8) {
                    activityMetric(
                        workout.summaryText,
                        icon:
                            workout.activity.icon
                    )

                    if workout.activity ==
                        .strength,
                       let count =
                            workout
                                .strengthExerciseCount,
                       count > 0 {
                        activityMetric(
                            ATHLTHLocalization.format(
                                english:
                                    "%d exercises",
                                norwegian:
                                    "%d øvelser",
                                count
                            ),
                            icon:
                                "list.bullet"
                        )
                    } else if let calories =
                                workout
                                    .activeEnergyKilocalories,
                              calories > 0 {
                        activityMetric(
                            "\(Int(calories.rounded())) kcal",
                            icon:
                                "flame.fill"
                        )
                    }
                }

                if let strengthWorkout,
                   !strengthWorkout
                    .exercises
                    .isEmpty {
                    Text(
                        strengthWorkout
                            .exercises
                            .prefix(3)
                            .map {
                                $0.exercise.name
                            }
                            .joined(
                                separator: " · "
                            )
                    )
                    .font(
                        .caption.weight(
                            .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
                }
            }
            .padding(15)
        }
        .background(
            Color.white.opacity(0.96),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
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
                Color.black.opacity(
                    0.045
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.045
                ),
            radius: 16,
            y: 7
        )
    }

    private func activityMetric(
        _ text: String,
        icon: String
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .caption.weight(
                .semibold
            )
        )
        .foregroundStyle(
            ATHLTHTheme.primaryText
        )
        .padding(
            .horizontal,
            9
        )
        .frame(height: 30)
        .background(
            Color.black.opacity(
                0.035
            ),
            in: Capsule()
        )
        .lineLimit(1)
    }
}

private struct HomePersonalCompactWorkoutCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    workout.activity.icon
            )
            .font(
                .system(
                    size: 15,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                workout.activity ==
                    .strength
                    ? ATHLTHTheme
                        .premiumGold
                    : ATHLTHTheme
                        .accentDeep
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                workout.activity ==
                    .strength
                    ? ATHLTHTheme
                        .champagneSoft
                    : ATHLTHTheme
                        .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(workout.title)
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Text(
                    compactSubtitle
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
            }

            Spacer(
                minLength: 0
            )
        }
        .padding(10)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(
                    0.035
                ),
                lineWidth: 0.7
            )
        }
    }

    private var compactSubtitle:
        String {
        if workout.activity ==
            .strength,
           let strengthWorkout {
            let count =
                strengthWorkout
                    .exercises
                    .filter {
                        $0.isCompleted ||
                        $0.sets.contains(
                            where: {
                                $0.isCompleted
                            }
                        )
                    }
                    .count

            if count > 0 {
                return ATHLTHLocalization.format(
                    english:
                        "%d exercises · %@",
                    norwegian:
                        "%d øvelser · %@",
                    count,
                    workout.summaryText
                )
            }
        }

        return workout.summaryText
    }
}

// MARK: - See all

struct HomePersonalActivityHistoryView:
    View {
    @EnvironmentObject private var health:
        HealthKitManager
    @EnvironmentObject private var strength:
        StrengthWorkoutStore
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @State private var workouts:
        [SocialPublishableWorkout] = []
    @State private var filter:
        HomePersonalActivityFilter =
            .all
    @State private var loading = false

    private var filtered:
        [SocialPublishableWorkout] {
        workouts.filter {
            filter.includes(
                $0.activity
            )
        }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.accent
                        .opacity(0.12)
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(
                    spacing: 14
                ) {
                    summaryHeader
                    filterBar

                    if loading &&
                        workouts.isEmpty {
                        ProgressView()
                            .padding(
                                .vertical,
                                60
                            )
                    } else if filtered.isEmpty {
                        emptyHistory
                    } else {
                        ForEach(
                            filtered
                        ) { workout in
                            NavigationLink {
                                HomePersonalActivityDestination(
                                    workout:
                                        workout,
                                    strengthWorkout:
                                        strengthWorkout(
                                            for:
                                                workout
                                        )
                                )
                            } label: {
                                HomePersonalHistoryCard(
                                    workout:
                                        workout,
                                    strengthWorkout:
                                        strengthWorkout(
                                            for:
                                                workout
                                        ),
                                    phoneWorkout:
                                        localPhoneWorkout(
                                            for:
                                                workout
                                        ),
                                    exerciseLibrary:
                                        exerciseLibrary
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(
                    .horizontal,
                    16
                )
                .padding(
                    .top,
                    10
                )
                .padding(
                    .bottom,
                    28
                )
                .frame(
                    maxWidth: 820
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .scrollIndicators(
                .hidden
            )
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Activity history",
                norwegian:
                    "Aktivitetshistorikk"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task {
            await load()
        }
        .refreshable {
            await load(
                forceRefresh: true
            )
        }
    }

    private var summaryHeader:
        some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "YOUR TRAINING",
                            norwegian:
                                "DIN TRENING"
                        )
                    )
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .tracking(1.7)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Everything you completed",
                            norwegian:
                                "Alt du har fullført"
                        )
                    )
                    .font(
                        .title2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "clock.arrow.circlepath"
                )
                .font(.title2)
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Circle()
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 9
            ) {
                summaryMetric(
                    "\(workouts.count)",
                    ATHLTHLocalization.choose(
                        english: "Sessions",
                        norwegian: "Økter"
                    )
                )

                summaryMetric(
                    runningDistanceText,
                    ATHLTHLocalization.choose(
                        english: "Run",
                        norwegian: "Løp"
                    )
                )

                summaryMetric(
                    "\(strengthCount)",
                    ATHLTHLocalization.choose(
                        english: "Strength",
                        norwegian: "Styrke"
                    )
                )
            }
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.96),
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.56)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.95
                ),
                lineWidth: 0.9
            )
        }
    }

    private var filterBar:
        some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 8) {
                ForEach(
                    HomePersonalActivityFilter
                        .allCases
                ) { option in
                    Button {
                        withAnimation(
                            .snappy(
                                duration: 0.22
                            )
                        ) {
                            filter =
                                option
                        }
                    } label: {
                        Text(option.title)
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                filter ==
                                    option
                                    ? Color.white
                                    : ATHLTHTheme
                                        .primaryText
                            )
                            .padding(
                                .horizontal,
                                14
                            )
                            .frame(
                                height: 34
                            )
                            .background(
                                filter ==
                                    option
                                    ? ATHLTHTheme
                                        .accentDeep
                                    : Color.white
                                        .opacity(
                                            0.88
                                        ),
                                in:
                                    Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyHistory:
        some View {
        ContentUnavailableView(
            ATHLTHLocalization.choose(
                english:
                    "No workouts here",
                norwegian:
                    "Ingen økter her"
            ),
            systemImage:
                "figure.run.circle",
            description:
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Completed workouts from ATHLTH and Apple Health appear automatically.",
                        norwegian:
                            "Fullførte økter fra ATHLTH og Apple Health vises automatisk."
                    )
                )
        )
        .padding(
            .vertical,
            48
        )
    }

    @MainActor
    private func load(
        forceRefresh: Bool = false
    ) async {
        loading = true
        defer {
            loading = false
        }

        if forceRefresh &&
            health
                .hasRequestedAuthorization {
            await health.refreshAll()
        }

        let healthSummaries:
            [WorkoutSummary]

        if health
            .hasRequestedAuthorization,
           let fetched =
                try? await health
                    .workoutHistory() {
            healthSummaries = fetched
        } else {
            healthSummaries =
                health.workouts
        }

        workouts =
            HomePersonalWorkoutCatalog
                .merge(
                    healthSummaries:
                        healthSummaries,
                    strengthHistory:
                        strength
                            .workoutHistory,
                    phoneHistory:
                        phoneWorkout
                            .history
                )
    }

    private func summaryMetric(
        _ value: String,
        _ title: String
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .headline.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.75
                )

            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(
            .vertical,
            10
        )
        .background(
            Color.white.opacity(
                0.64
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
        )
    }

    private var runningDistanceText:
        String {
        let meters =
            workouts
                .filter {
                    $0.activity ==
                        .running
                }
                .compactMap(
                    \.distanceMeters
                )
                .reduce(0, +)

        guard meters > 0 else {
            return "—"
        }

        return String(
            format: "%.1f km",
            meters / 1_000
        )
    }

    private var strengthCount:
        Int {
        workouts.filter {
            $0.activity ==
                .strength
        }
        .count
    }

    private func strengthWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> StrengthWorkoutLog? {
        HomePersonalWorkoutCatalog
            .strengthWorkout(
                for: workout,
                in:
                    strength
                        .workoutHistory
            )
    }

    private func localPhoneWorkout(
        for workout:
            SocialPublishableWorkout
    ) -> PhoneWorkout? {
        HomePersonalWorkoutCatalog
            .phoneWorkout(
                for: workout,
                in:
                    phoneWorkout
                        .history
            )
    }
}

private struct HomePersonalHistoryCard:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HomePersonalWorkoutVisual(
                workout: workout,
                strengthWorkout:
                    strengthWorkout,
                phoneWorkout:
                    phoneWorkout,
                exerciseLibrary:
                    exerciseLibrary,
                height: 184
            )

            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(workout.title)
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                        Text(
                            workout.startDate
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Text(workout.source)
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .padding(
                            .horizontal,
                            8
                        )
                        .frame(height: 26)
                        .background(
                            Color.black.opacity(
                                0.035
                            ),
                            in: Capsule()
                        )
                }

                metricRow

                if workout.activity ==
                    .strength,
                   let strengthWorkout {
                    let exerciseNames =
                        strengthWorkout
                            .exercises
                            .filter {
                                $0.isCompleted ||
                                $0.sets.contains(
                                    where: {
                                        $0.isCompleted
                                    }
                                )
                            }
                            .prefix(4)
                            .map {
                                $0.exercise.name
                            }

                    if !exerciseNames.isEmpty {
                        Text(
                            exerciseNames
                                .joined(
                                    separator:
                                        " · "
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                    }
                }
            }
            .padding(16)
        }
        .background(
            Color.white.opacity(0.96),
            in:
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(
                    0.04
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.045
                ),
            radius: 16,
            y: 7
        )
    }

    private var metricRow:
        some View {
        HStack(spacing: 0) {
            historyMetric(
                ATHLTHLocalization.choose(
                    english: "Time",
                    norwegian: "Tid"
                ),
                durationText
            )

            metricDivider

            if workout.activity ==
                .strength {
                historyMetric(
                    ATHLTHLocalization.choose(
                        english:
                            "Exercises",
                        norwegian:
                            "Øvelser"
                    ),
                    workout
                        .strengthExerciseCount
                        .map(String.init) ??
                    "—"
                )
            } else {
                historyMetric(
                    ATHLTHLocalization.choose(
                        english:
                            "Distance",
                        norwegian:
                            "Distanse"
                    ),
                    distanceText
                )
            }

            metricDivider

            historyMetric(
                workout.activity ==
                    .strength
                    ? ATHLTHLocalization
                        .choose(
                            english:
                                "Volume",
                            norwegian:
                                "Volum"
                        )
                    : ATHLTHLocalization
                        .choose(
                            english:
                                "Energy",
                            norwegian:
                                "Energi"
                        ),
                tertiaryMetricText
            )
        }
    }

    private func historyMetric(
        _ title: String,
        _ value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(title.uppercased())
                .font(
                    .system(
                        size: 8.5,
                        weight: .bold
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

            Text(value)
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var metricDivider:
        some View {
        Rectangle()
            .fill(
                Color.black.opacity(
                    0.06
                )
            )
            .frame(
                width: 1,
                height: 28
            )
            .padding(
                .horizontal,
                10
            )
    }

    private var durationText:
        String {
        let totalMinutes =
            max(
                Int(
                    (
                        workout.duration /
                        60
                    )
                    .rounded()
                ),
                0
            )

        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }

        return "\(totalMinutes) min"
    }

    private var distanceText:
        String {
        guard let meters =
                workout
                    .distanceMeters,
              meters > 0
        else {
            return "—"
        }

        return String(
            format: "%.2f km",
            meters / 1_000
        )
    }

    private var tertiaryMetricText:
        String {
        if workout.activity ==
            .strength,
           let volume =
                workout
                    .strengthTotalVolumeKilograms,
           volume > 0 {
            if volume >= 1_000 {
                return String(
                    format:
                        "%.1f t",
                    volume / 1_000
                )
            }

            return String(
                format: "%.0f kg",
                volume
            )
        }

        if let calories =
                workout
                    .activeEnergyKilocalories,
           calories > 0 {
            return "\(Int(calories.rounded())) kcal"
        }

        return "—"
    }
}

// MARK: - Visual preview

private struct HomePersonalWorkoutVisual:
    View {
    @EnvironmentObject private var health:
        HealthKitManager

    @EnvironmentObject private var exerciseLibrary:
        ExerciseLibraryStore

    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?
    let phoneWorkout: PhoneWorkout?
    let height: CGFloat

    @State private var detail:
        WorkoutDetail?

    private var localRoute:
        [CLLocation] {
        phoneWorkout?
            .points
            .map(\.location) ??
        []
    }

    private var resolvedRoute:
        [CLLocation] {
        if localRoute.count >= 2 {
            return localRoute
        }

        return detail?.route ?? []
    }

    private var muscleProfile:
        StrengthMuscleProfile {
        guard let strengthWorkout else {
            return StrengthMuscleProfile(
                activations: []
            )
        }

        return StrengthMuscleProfileBuilder
            .make(
                workout:
                    strengthWorkout,
                library:
                    exerciseLibrary
                        .allExercises
            )
            .profile
    }

    var body: some View {
        ZStack {
            background

            VStack {
                HStack {
                    Label(
                        activityLabel,
                        systemImage:
                            workout
                                .activity
                                .icon
                    )
                    .font(
                        .caption.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.92
                        )
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .frame(height: 30)
                    .background(
                        Color.black.opacity(
                            0.24
                        ),
                        in: Capsule()
                    )

                    Spacer()
                }

                Spacer()
            }
            .padding(12)
        }
        .frame(height: height)
        .clipped()
        .task(id: workout.id) {
            await loadDetailIfNeeded()
        }
    }

    @ViewBuilder
    private var background:
        some View {
        if workout.activity ==
            .strength {
            strengthBackground
        } else if isOutdoorActivity,
                  resolvedRoute.count >= 2 {
            routeMap
        } else {
            genericBackground
        }
    }

    private var strengthBackground:
        some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(
                        red: 0.10,
                        green: 0.17,
                        blue: 0.14
                    ),
                    Color(
                        red: 0.04,
                        green: 0.06,
                        blue: 0.07
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            if !muscleProfile
                .activations
                .isEmpty {
                HStack {
                    Spacer()

                    StrengthMuscleMapView(
                        profile:
                            muscleProfile,
                        compact: true
                    )
                    .frame(
                        width:
                            min(
                                height * 1.08,
                                205
                            ),
                        height:
                            max(
                                height - 18,
                                120
                            )
                    )
                    .padding(
                        .trailing,
                        12
                    )
                    .opacity(0.94)
                }
            } else {
                Image(
                    systemName:
                        "figure.strengthtraining.traditional"
                )
                .font(
                    .system(
                        size:
                            min(
                                height * 0.54,
                                92
                            ),
                        weight: .medium
                    )
                )
                .symbolRenderingMode(
                    .hierarchical
                )
                .foregroundStyle(
                    Color.white.opacity(
                        0.15
                    )
                )
                .offset(
                    x: 86
                )
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(
                        0.10
                    ),
                    Color.clear,
                    Color.black.opacity(
                        0.22
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )
        }
    }

    private var routeMap:
        some View {
        Map(
            initialPosition:
                .region(
                    routeRegion(
                        resolvedRoute
                            .map(
                                \.coordinate
                            )
                    )
                )
        ) {
            MapPolyline(
                coordinates:
                    resolvedRoute
                        .map(
                            \.coordinate
                        )
            )
            .stroke(
                ATHLTHTheme.accent,
                lineWidth: 5
            )
        }
        .allowsHitTesting(false)
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(
                        0.10
                    ),
                    Color.clear,
                    Color.black.opacity(
                        0.18
                    )
                ],
                startPoint:
                    .top,
                endPoint:
                    .bottom
            )
        }
    }

    private var genericBackground:
        some View {
        ZStack {
            LinearGradient(
                colors: [
                    visualAccent
                        .opacity(0.88),
                    Color(
                        red: 0.07,
                        green: 0.08,
                        blue: 0.10
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            Image(
                systemName:
                    workout.activity.icon
            )
            .font(
                .system(
                    size:
                        min(
                            height * 0.56,
                            96
                        ),
                    weight: .medium
                )
            )
            .symbolRenderingMode(
                .hierarchical
            )
            .foregroundStyle(
                Color.white.opacity(
                    0.13
                )
            )
            .offset(x: 94)
        }
    }

    @MainActor
    private func loadDetailIfNeeded()
        async {
        guard isOutdoorActivity,
              localRoute.count < 2,
              detail == nil
        else {
            return
        }

        let fetched =
            await health.workoutDetail(
                for: workout.id
            )

        guard !Task.isCancelled else {
            return
        }

        detail = fetched
    }

    private var isOutdoorActivity:
        Bool {
        switch workout.activity {
        case .running,
             .walking,
             .cycling,
             .hiking:
            return true
        default:
            return false
        }
    }

    private var activityLabel:
        String {
        switch workout.activity {
        case .running:
            return ATHLTHLocalization.choose(
                english: "RUN",
                norwegian: "LØP"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "WALK",
                norwegian: "GÅTUR"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "STRENGTH",
                norwegian: "STYRKE"
            )
        default:
            return workout
                .activity
                .rawValue
                .uppercased()
        }
    }

    private var visualAccent:
        Color {
        switch workout.activity {
        case .running,
             .walking,
             .hiking:
            return ATHLTHTheme
                .vitality
        case .strength:
            return ATHLTHTheme
                .premiumGold
        default:
            return ATHLTHTheme
                .accentDeep
        }
    }

    private func routeRegion(
        _ coordinates:
            [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta:
                            0.02,
                        longitudeDelta:
                            0.02
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
            coordinates.dropFirst() {
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

        let center =
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
            )

        return MKCoordinateRegion(
            center: center,
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (
                                maxLatitude -
                                minLatitude
                            ) * 1.35,
                            0.006
                        ),
                    longitudeDelta:
                        max(
                            (
                                maxLongitude -
                                minLongitude
                            ) * 1.35,
                            0.006
                        )
                )
        )
    }
}

private struct HomePersonalActivityDestination:
    View {
    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?

    var body: some View {
        Group {
            switch workout.activity {
            case .running,
                 .walking,
                 .hiking:
                HomeActivityRunDetailView(
                    workout: workout,
                    initialDetail: nil,
                    initialAIInsight:
                        nil
                )

            case .strength:
                HomeActivityStrengthDetailView(
                    workout: workout,
                    strengthWorkout:
                        strengthWorkout
                )

            default:
                WorkoutHistoryDetailView(
                    workout: workout
                )
            }
        }
    }
}
