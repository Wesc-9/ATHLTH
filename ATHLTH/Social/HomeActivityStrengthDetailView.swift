import SwiftUI

struct HomeActivityStrengthDetailView: View {
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore

    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?

    @State private var aiInsight: WorkoutAIInsight?
    @State private var isLoadingAIInsight = false

    private var muscleSummary:
        StrengthMuscleSessionSummary {
        guard let strengthWorkout else {
            return .empty
        }

        return StrengthMuscleProfileBuilder
            .make(
                workout: strengthWorkout,
                library:
                    exerciseLibrary
                        .allExercises
            )
    }

    private var figureStyle:
        StrengthBodyPresentation {
        switch settings
            .strengthFigurePreference {
        case .female:
            return .female
        case .male:
            return .male
        case .neutral:
            return .neutral
        case .automatic:
            let healthSex =
                session
                    .onboardingProfile?
                    .healthSex ??
                health
                    .personalDetails
                    .healthSex

            switch healthSex {
            case .female:
                return .female
            case .male:
                return .male
            case .other,
                 .preferNotToSay,
                 .none:
                return .neutral
            }
        }
    }

    private var activationTint:
        Color {
        Color(
            red: 0.91,
            green: 0.54,
            blue: 0.24
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overviewCard

                if workout.allowsTrainingPlaceCheckIn {
                    WorkoutPlaceCheckInSection(
                        workoutID: workout.id
                    )
                }

                muscleMapCard

                exercisesCard

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
            "Strength details"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task(id: workout.id) {
            await loadCoachInsight()
        }
    }

    private var overviewCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Label(
                        "Strength",
                        systemImage:
                            "dumbbell.fill"
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
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                if let source =
                    strengthWorkout?
                        .captureDevice
                        .title {
                    Text(source)
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .padding(
                            .horizontal,
                            8
                        )
                        .padding(
                            .vertical,
                            5
                        )
                        .background(
                            ATHLTHTheme
                                .surfaceStone,
                            in: Capsule()
                        )
                }
            }

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
                .lineLimit(2)

            ViewThatFits(
                in: .horizontal
            ) {
                HStack(spacing: 0) {
                    overviewMetric(
                        "Duration",
                        durationText
                    )
                    overviewDivider
                    overviewMetric(
                        "Exercises",
                        exerciseCountText
                    )
                    overviewDivider
                    overviewMetric(
                        "Sets",
                        setsText
                    )
                    overviewDivider
                    overviewMetric(
                        "Volume",
                        volumeText
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {
                    overviewMetric(
                        "Duration",
                        durationText
                    )
                    overviewMetric(
                        "Exercises",
                        exerciseCountText
                    )
                    overviewMetric(
                        "Sets",
                        setsText
                    )
                    overviewMetric(
                        "Volume",
                        volumeText
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

    private var muscleMapCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text("Muscle focus")
                        .font(
                            .headline.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        "Based on the exercises and completed sets in this session."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            if muscleSummary
                .profile
                .activations
                .isEmpty {
                ZStack(
                    alignment: .bottomLeading
                ) {
                    Image(
                        "StrengthPostWorkoutHero"
                    )
                    .resizable()
                    .scaledToFill()
                    .frame(
                        maxWidth:
                            .infinity,
                        minHeight: 250,
                        maxHeight: 250
                    )
                    .clipped()
                    .saturation(0.72)
                    .contrast(0.94)

                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white
                                .opacity(0.18),
                            Color.white
                                .opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Strength session",
                                norwegian:
                                    "Styrkeøkt"
                            )
                        )
                        .font(
                            .headline.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Muscle focus appears when the recorded exercises include muscle metadata.",
                                norwegian:
                                    "Muskelfokus vises når de registrerte øvelsene inneholder muskeldata."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .padding(15)
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
            } else {
                HStack(
                    alignment: .center,
                    spacing: 18
                ) {
                    StrengthMuscleMapView(
                        profile:
                            muscleSummary
                                .profile,
                        figureStyle:
                            figureStyle,
                        activationTint:
                            activationTint
                    )
                    .frame(
                        width: 168,
                        height: 300
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(
                            Array(
                                muscleSummary
                                    .profile
                                    .topActivations
                                    .prefix(5)
                            )
                        ) { activation in
                            muscleLoadRow(
                                activation
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }

                Text(
                    "The shading is a relative session-focus estimate from primary/secondary exercise roles and set count. It is not a measured muscle-activation percentage."
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.995,
                            green: 0.990,
                            blue: 0.978
                        ),
                        Color.white
                            .opacity(0.985)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        activationTint
                            .opacity(0.095),
                        Color.clear
                    ],
                    center:
                        .topTrailing,
                    startRadius: 8,
                    endRadius: 320
                )
            },
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

    private var exercisesCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            Text("Exercises")
                .font(
                    .headline.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            if muscleSummary
                .exercises
                .isEmpty {
                Text(
                    "No exercise breakdown is available for this workout."
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            } else {
                ForEach(
                    Array(
                        muscleSummary
                            .exercises
                            .enumerated()
                    ),
                    id: \.element.id
                ) {
                    index,
                    exercise in

                    if index > 0 {
                        Divider()
                            .opacity(0.55)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        HStack(
                            alignment:
                                .firstTextBaseline
                        ) {
                            Text(
                                exercise.name
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                            Spacer()

                            Text(
                                exerciseMetricText(
                                    exercise
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        if !exercise
                            .primaryMuscles
                            .isEmpty {
                            muscleRoleRow(
                                title: "Primary",
                                muscles:
                                    exercise
                                        .primaryMuscles,
                                isPrimary: true
                            )
                        }

                        if !exercise
                            .secondaryMuscles
                            .isEmpty {
                            muscleRoleRow(
                                title:
                                    "Secondary",
                                muscles:
                                    exercise
                                        .secondaryMuscles,
                                isPrimary: false
                            )
                        }
                    }
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
                        ATHLTHTheme
                            .champagneSoft,
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
                    "Coach is analyzing exercise selection, set volume and muscle focus…"
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            } else {
                Text(
                    coachUnavailableText
                )
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
    private func loadCoachInsight() async {
        guard aiInsight == nil,
              !isLoadingAIInsight,
              session.hasPaidAccess,
              session
                .aiHealthDataSharingEnabled,
              strengthWorkout != nil
        else {
            return
        }

        isLoadingAIInsight = true
        defer {
            isLoadingAIInsight = false
        }

        var context =
            WorkoutAIInsightContext(
                activity: "Strength",
                durationSeconds:
                    workout.duration,
                distanceMeters: nil,
                activeEnergyKilocalories:
                    workout
                        .activeEnergyKilocalories,
                averageHeartRateBPM:
                    strengthWorkout?
                        .healthMetrics
                        .averageHeartRate,
                maxHeartRateBPM:
                    strengthWorkout?
                        .healthMetrics
                        .maxHeartRate,
                personalMaximumHeartRateBPM:
                    session
                        .onboardingProfile?
                        .maximumHeartRateBPM,
                elevationGainMeters: nil,
                routePointCount: 0,
                averagePaceSecondsPerKilometer:
                    nil,
                averageRunningPowerWatts:
                    nil,
                averageRunningStrideLengthMeters:
                    nil,
                averageRunningVerticalOscillationCentimeters:
                    nil,
                averageRunningGroundContactTimeMilliseconds:
                    nil,
                segments: []
            )

        context.strengthTotalSets =
            muscleSummary.totalSets
        context.strengthTotalReps =
            muscleSummary.totalReps
        context
            .strengthTotalVolumeKilograms =
            muscleSummary
                .totalVolumeKilograms >
                0
                ? muscleSummary
                    .totalVolumeKilograms
                : nil
        context.strengthMuscleFocus =
            muscleSummary
                .profile
                .topActivations
                .prefix(8)
                .map {
                    $0.region.title
                }
        context.strengthExercises =
            muscleSummary
                .exercises
                .prefix(16)
                .map {
                    WorkoutStrengthExerciseContext(
                        name: $0.name,
                        completedSets:
                            $0.completedSets,
                        totalReps:
                            $0.totalReps >
                            0
                            ? $0.totalReps
                            : nil,
                        volumeKilograms:
                            $0.volumeKilograms >
                            0
                            ? $0.volumeKilograms
                            : nil,
                        primaryMuscles:
                            $0.primaryMuscles,
                        secondaryMuscles:
                            $0.secondaryMuscles
                    )
                }

        do {
            aiInsight =
                try await
                WorkoutInsightAIService()
                    .generate(
                        workoutID:
                            workout.id,
                        context: context
                    )
        } catch {
            // Keep the detail page fully useful when Coach is unavailable.
        }
    }

    private func muscleLoadRow(
        _ activation:
            StrengthMuscleActivation
    ) -> some View {
        let intensity =
            muscleSummary
                .profile
                .intensity(
                    for:
                        activation.region
                )

        return VStack(
            alignment: .leading,
            spacing: 5
        ) {
            HStack {
                Text(
                    activation
                        .region
                        .title
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Spacer()

                Text(
                    loadLabel(
                        intensity
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            GeometryReader {
                geometry in
                ZStack(
                    alignment: .leading
                ) {
                    Capsule()
                        .fill(
                            Color.black
                                .opacity(
                                    0.06
                                )
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    activationTint
                                        .opacity(0.62),
                                    ATHLTHTheme
                                        .premiumGold
                                ],
                                startPoint:
                                    .leading,
                                endPoint:
                                    .trailing
                            )
                        )
                        .frame(
                            width:
                                geometry
                                    .size
                                    .width *
                                intensity
                        )
                }
            }
            .frame(height: 6)
        }
    }

    private func muscleRoleRow(
        title: String,
        muscles: [String],
        isPrimary: Bool
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .frame(
                    width: 60,
                    alignment: .leading
                )

            Text(
                muscles
                    .map(displayMuscleName)
                    .joined(
                        separator: " · "
                    )
            )
            .font(
                .caption.weight(
                    isPrimary
                        ? .semibold
                        : .regular
                )
            )
            .foregroundStyle(
                isPrimary
                    ? ATHLTHTheme
                        .primaryText
                    : ATHLTHTheme
                        .mutedText
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
    }

    private func exerciseMetricText(
        _ exercise:
            StrengthExerciseMuscleSummary
    ) -> String {
        var values: [String] = []

        if exercise.completedSets > 0 {
            values.append(
                "\(exercise.completedSets) sets"
            )
        }

        if exercise.totalReps > 0 {
            values.append(
                "\(exercise.totalReps) reps"
            )
        }

        if exercise.volumeKilograms >
            0 {
            values.append(
                volumeString(
                    exercise
                        .volumeKilograms
                )
            )
        }

        return values.isEmpty
            ? "Recorded"
            : values.joined(
                separator: " · "
            )
    }

    private func overviewMetric(
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

    private var overviewDivider: some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider
            )
            .frame(
                width: 1,
                height: 34
            )
    }

    private var displayTitle: String {
        let value =
            workout.title
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if value.isEmpty ||
            value
                .lowercased()
                .contains(
                    "strength"
                ) {
            let focus =
                muscleSummary
                    .profile
                    .topActivations
                    .prefix(2)
                    .map {
                        $0.region.title
                    }

            if !focus.isEmpty {
                return
                    focus.joined(
                        separator: " + "
                    ) +
                    " session"
            }

            return "Strength session"
        }

        return value
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

        if hours > 0 {
            return
                "\(hours)h \(minutes)m"
        }

        return
            "\(minutes) min"
    }

    private var exerciseCountText: String {
        let count =
            muscleSummary
                .exercises
                .count

        if count > 0 {
            return "\(count)"
        }

        if let count =
            workout
                .strengthExerciseCount {
            return "\(count)"
        }

        return "—"
    }

    private var setsText: String {
        muscleSummary.totalSets > 0
            ? "\(muscleSummary.totalSets)"
            : "—"
    }

    private var volumeText: String {
        if muscleSummary
            .totalVolumeKilograms >
            0 {
            return volumeString(
                muscleSummary
                    .totalVolumeKilograms
            )
        }

        if let value =
            workout
                .strengthTotalVolumeKilograms,
           value > 0 {
            return volumeString(
                value
            )
        }

        return "—"
    }

    private func volumeString(
        _ value: Double
    ) -> String {
        if value >= 1_000 {
            return String(
                format:
                    "%.1f t",
                value / 1_000
            )
        }

        return String(
            format:
                "%.0f kg",
            value
        )
    }

    private func loadLabel(
        _ intensity: Double
    ) -> String {
        switch intensity {
        case 0.78...:
            return "Primary focus"
        case 0.48..<0.78:
            return "Strong"
        case 0.25..<0.48:
            return "Moderate"
        default:
            return "Supporting"
        }
    }

    private func displayMuscleName(
        _ raw: String
    ) -> String {
        raw
            .replacingOccurrences(
                of: "_",
                with: " "
            )
            .split(separator: " ")
            .map {
                $0.capitalized
            }
            .joined(
                separator: " "
            )
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

        if strengthWorkout == nil {
            return
                "Detailed strength data is not available for this workout."
        }

        return
            "Coach insight is not available for this workout yet."
    }
}
