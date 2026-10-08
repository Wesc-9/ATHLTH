import SwiftUI

struct HomeActivityStrengthDetailView: View {
    private struct RestTimelineEntry:
        Identifiable
    {
        let id: String
        let title: String
        let subtitle: String?
        let seconds: TimeInterval
        let systemImage: String
    }

    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let workout: SocialPublishableWorkout
    let strengthWorkout: StrengthWorkoutLog?

    @State private var aiInsight: WorkoutAIInsight?
    @State private var isLoadingAIInsight = false
    @State private var editingSetResult:
        StrengthSetResultEditTarget?

    private var resolvedStrengthWorkout:
        StrengthWorkoutLog? {
        guard let strengthWorkout else {
            return nil
        }

        return strength.workoutHistory.first(
            where: {
                $0.id == strengthWorkout.id
            }
        ) ??
        strengthWorkout
    }

    private var editableStrengthWorkout:
        StrengthWorkoutLog? {
        guard let strengthWorkout else {
            return nil
        }

        return strength.workoutHistory.first(
            where: {
                $0.id == strengthWorkout.id
            }
        )
    }

    private var muscleSummary:
        StrengthMuscleSessionSummary {
        guard let strengthWorkout =
                resolvedStrengthWorkout
        else {
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

    private var activationTint:
        Color {
        Color(
            red: 0.93,
            green: 0.32,
            blue: 0.22
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                workoutHeroCard

                overviewCard

                // The finished-workout muscle map was previously defined
                // but never placed in this view's scroll hierarchy.
                // Show it only when actual exercise-derived muscles exist.
                if !muscleSummary.profile.activations.isEmpty {
                    muscleMapCard
                }

                if hasRestFlowData {
                    restFlowCard
                }

                exerciseBreakdownSection

                if !workoutPersonalRecords.isEmpty {
                    performanceCard
                }

                if hasHealthMetrics {
                    healthMetricsCard
                }

                coachCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
            // The vertical ScrollView must use the device viewport width.
            // Otherwise a scaled-to-fill hero can make the entire detail
            // page wider than the iPhone and cut off both edges.
            .containerRelativeFrame(.horizontal)
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
            ATHLTHLocalization.choose(
                english: "Strength details",
                norwegian: "Styrkedetaljer"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task(id: workout.id) {
            await loadCoachInsight()
        }
        .sheet(
            item: $editingSetResult
        ) { target in
            StrengthSetResultEditorView(
                target: target
            ) {
                segments,
                distanceMeters,
                resistanceLevel in

                guard let workout =
                        editableStrengthWorkout
                else {
                    return
                }

                strength.updateCompletedSetResult(
                    workoutID: workout.id,
                    exerciseID:
                        target.exerciseID,
                    setID: target.set.id,
                    segments: segments,
                    distanceMeters:
                        distanceMeters,
                    resistanceLevel:
                        resistanceLevel
                )
                editingSetResult = nil
                aiInsight = nil
            }
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
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Workout at a glance",
                            norwegian:
                                "Økta i tall"
                        )
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
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
                    resolvedStrengthWorkout?
                        .captureDevice
                        .title {
                    Label(
                        source,
                        systemImage:
                            source ==
                                "Apple Watch"
                                ? "applewatch"
                                : "iphone"
                    )
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
                        9
                    )
                    .padding(
                        .vertical,
                        6
                    )
                    .background(
                        ATHLTHTheme
                            .surfaceStone,
                        in: Capsule()
                    )
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 8
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 8
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 8
                    )
                ],
                spacing: 8
            ) {
                sessionMetricTile(
                    icon: "timer",
                    label:
                        ATHLTHLocalization.choose(
                            english: "Time",
                            norwegian: "Tid"
                        ),
                    value: durationText
                )

                sessionMetricTile(
                    icon: "dumbbell.fill",
                    label:
                        ATHLTHLocalization.choose(
                            english: "Exercises",
                            norwegian: "Øvelser"
                        ),
                    value: exerciseCountText
                )

                sessionMetricTile(
                    icon: "square.stack.3d.up.fill",
                    label:
                        ATHLTHLocalization.choose(
                            english: "Sets",
                            norwegian: "Sett"
                        ),
                    value: setsText
                )

                sessionMetricTile(
                    icon:
                        "repeat.circle.fill",
                    label:
                        ATHLTHLocalization.choose(
                            english: "Reps",
                            norwegian: "Reps"
                        ),
                    value: repsText
                )

                sessionMetricTile(
                    icon:
                        "scalemass.fill",
                    label:
                        ATHLTHLocalization.choose(
                            english: "Volume",
                            norwegian: "Volum"
                        ),
                    value: volumeText
                )

                sessionMetricTile(
                    icon:
                        "pause.circle.fill",
                    label:
                        ATHLTHLocalization.choose(
                            english: "Rest",
                            norwegian: "Pause"
                        ),
                    value:
                        restSummaryText
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

    private func sessionMetricTile(
        icon: String,
        label: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Image(
                systemName: icon
            )
            .font(
                .caption.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )

            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 70,
            alignment: .leading
        )
        .padding(10)
        .background(
            ATHLTHTheme
                .surfaceStone
                .opacity(0.72),
            in:
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
        )
    }

    // The detail hero uses the media for the exercise that best represents
    // this completed session. Home deliberately keeps the lightweight
    // anatomical doll so the activity stream remains fast and scannable.
    private var representativeExerciseEntry:
        ExerciseLibraryEntry? {
        guard let strengthWorkout =
                resolvedStrengthWorkout
        else {
            return nil
        }

        let performed =
            strengthWorkout.exercises
                .filter {
                    $0.isCompleted ||
                    $0.sets.contains(
                        where: \.isCompleted
                    )
                }
                .sorted { lhs, rhs in
                    let lhsSets =
                        lhs.sets
                            .filter(
                                \.countsTowardTrainingLoad
                            )
                            .count
                    let rhsSets =
                        rhs.sets
                            .filter(
                                \.countsTowardTrainingLoad
                            )
                            .count

                    return lhsSets > rhsSets
                }

        guard !performed.isEmpty else {
            return nil
        }

        let catalog =
            exerciseLibrary
                .allExercises

        for loggedExercise in performed {
            if let plannedID =
                    loggedExercise
                        .plannedExerciseID,
               let exact =
                    catalog.first(
                        where: {
                            $0.id ==
                                plannedID
                        }
                    ) {
                return exact
            }

            let loggedName =
                loggedExercise
                    .exercise
                    .name
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

            guard !loggedName.isEmpty else {
                continue
            }

            if let named =
                catalog.first(
                    where: { entry in
                        entry.canonicalName
                            .localizedCaseInsensitiveCompare(
                                loggedName
                            ) ==
                            .orderedSame ||
                        entry.name
                            .localizedCaseInsensitiveCompare(
                                loggedName
                            ) ==
                            .orderedSame
                    }
                ) {
                return named
            }
        }

        return nil
    }

    private var representativeExerciseName:
        String? {
        guard let strengthWorkout =
                resolvedStrengthWorkout
        else {
            return nil
        }

        return strengthWorkout.exercises
            .filter {
                $0.isCompleted ||
                $0.sets.contains(
                    where: \.isCompleted
                )
            }
            .max { lhs, rhs in
                lhs.sets
                    .filter(
                        \.countsTowardTrainingLoad
                    )
                    .count <
                rhs.sets
                    .filter(
                        \.countsTowardTrainingLoad
                    )
                    .count
            }?
            .exercise
            .name
    }

    private var workoutHeroImageURL:
        URL? {
        guard let entry =
                representativeExerciseEntry
        else {
            return nil
        }

        return entry.imagePeakURL ??
            entry.imageStartURL ??
            entry.exercise.imageURL
    }

    private var workoutHeroFocusText:
        String {
        if let focus =
                muscleSummary
                    .profile
                    .topActivations
                    .first?
                    .region
                    .activityDisplayTitle {
            return focus.uppercased()
        }

        if let bodyPart =
                representativeExerciseEntry?
                    .bodyPart?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
           !bodyPart.isEmpty {
            return bodyPart.uppercased()
        }

        return ATHLTHLocalization.choose(
            english: "STRENGTH",
            norwegian: "STYRKE"
        )
    }

    private var workoutHeroMetricText:
        String {
        var values: [String] = [
            workoutHeroFocusText
        ]

        if muscleSummary.totalSets > 0 {
            values.append(
                ATHLTHLocalization.format(
                    english: "%d SETS",
                    norwegian: "%d SETT",
                    muscleSummary.totalSets
                )
            )
        }

        if muscleSummary.totalReps > 0 {
            values.append(
                ATHLTHLocalization.format(
                    english: "%d REPS",
                    norwegian: "%d REPS",
                    muscleSummary.totalReps
                )
            )
        }

        return values.joined(
            separator: " · "
        )
    }

    private var workoutHeroCard:
        some View {
        GeometryReader { viewport in
            ZStack(alignment: .bottomLeading) {
                workoutHeroArtwork
                    .frame(width: viewport.size.width, height: 196)
                    .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "STRENGTH",
                        norwegian: "STYRKE"
                    ),
                    systemImage:
                        "dumbbell.fill"
                )
                .font(
                    .caption2.weight(
                        .bold
                    )
                )
                .tracking(1.2)
                .foregroundStyle(
                    Color.white
                        .opacity(0.92)
                )

                Text(displayTitle)
                    .font(
                        .title2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(
                        workout.startDate
                            .formatted(
                                date:
                                    .abbreviated,
                                time:
                                    .shortened
                            )
                    )

                    if let source =
                            resolvedStrengthWorkout?
                                .captureDevice
                                .title {
                        Text("·")
                        Text(source)
                    }
                }
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    Color.white
                        .opacity(0.86)
                )
            }
            .padding(16)
        }
        .frame(width: viewport.size.width, height: 196)
        .clipShape(
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
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            displayTitle
        )
        }
        .frame(height: 196)
    }

    @ViewBuilder
    private var workoutHeroArtwork:
        some View {
        // A completed strength session should read as strength at a glance.
        // Exercise-specific art remains useful in the library, but here it
        // made rowing/cardio-machine imagery dominate the whole workout.
        workoutHeroFallback
    }

    private var workoutHeroFallback:
        some View {
        Image(
            "StrengthPostWorkoutHero"
        )
        .resizable()
        .scaledToFill()
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
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Muscle focus",
                            norwegian: "Muskelfokus"
                        )
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Based on the exercises and completed sets in this session.",
                            norwegian: "Basert på øvelser og fullførte sett i denne økten."
                        )
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
                        presentation:
                            .home,
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

                if !muscleSummary.profile.primaryRegions.isEmpty ||
                   !muscleSummary.profile.secondaryRegions.isEmpty {
                    HStack(spacing: 17) {
                        if !muscleSummary.profile.primaryRegions.isEmpty {
                            Label {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Primary",
                                        norwegian: "Primær"
                                    )
                                )
                            } icon: {
                                Circle()
                                    .fill(activationTint.opacity(0.94))
                                    .frame(width: 9, height: 9)
                            }
                        }
                        if !muscleSummary.profile.secondaryRegions.isEmpty {
                            Label {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Supporting",
                                        norwegian: "Sekundær"
                                    )
                                )
                            } icon: {
                                Circle()
                                    .fill(activationTint.opacity(0.39))
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Text(
                    ATHLTHLocalization.choose(
                        english: "Colors estimate relative muscle focus from exercises and completed sets, not measured activation.",
                        norwegian: "Fargene anslår muskelfokus basert på øvelser og fullførte sett – ikke målt muskelaktivering."
                    )
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
            LinearGradient(
                colors: [
                    Color(
                        red: 0.995,
                        green: 0.990,
                        blue: 0.978
                    ),
                    activationTint
                        .opacity(0.055),
                    Color.white
                        .opacity(0.985)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
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
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    private var hasRestFlowData: Bool {
        totalRestSeconds > 0 ||
        totalTransitionSeconds > 0
    }

    private var totalRestSeconds:
        TimeInterval {
        resolvedStrengthWorkout?
            .totalActualRestSeconds ??
        0
    }

    private var averageRestSeconds:
        TimeInterval {
        resolvedStrengthWorkout?
            .averageActualRestSeconds ??
        0
    }

    private var longestRestSeconds:
        TimeInterval {
        resolvedStrengthWorkout?
            .longestActualRestSeconds ??
        0
    }

    private var totalTransitionSeconds:
        TimeInterval {
        resolvedStrengthWorkout?
            .exercises
            .compactMap(
                \.transitionToNextExerciseSeconds
            )
            .reduce(0, +) ??
        0
    }

    private var restTimeline:
        [RestTimelineEntry] {
        guard let strengthWorkout =
                resolvedStrengthWorkout
        else {
            return []
        }

        var result:
            [RestTimelineEntry] = []

        for (
            exerciseIndex,
            exercise
        ) in strengthWorkout
            .exercises
            .enumerated() {
            for set in exercise.sets
            where set.isCompleted {
                guard
                    let rest =
                        set.actualRestAfterSeconds,
                    rest > 0
                else {
                    continue
                }

                result.append(
                    RestTimelineEntry(
                        id:
                            "set-\(set.id.uuidString)",
                        title:
                            exercise.exercise
                                .displayName,
                        subtitle:
                            ATHLTHLocalization.format(
                                english:
                                    "After set %d",
                                norwegian:
                                    "Etter sett %d",
                                set.setNumber
                            ),
                        seconds: rest,
                        systemImage:
                            "pause.fill"
                    )
                )
            }

            if exerciseIndex <
                    strengthWorkout
                        .exercises
                        .count - 1,
               let transition =
                    exercise
                        .transitionToNextExerciseSeconds,
               transition > 0 {
                result.append(
                    RestTimelineEntry(
                        id:
                            "transition-\(exercise.id.uuidString)",
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Exercise change",
                                norwegian:
                                    "Bytte av øvelse"
                            ),
                        subtitle:
                            exercise.exercise
                                .displayName,
                        seconds:
                            transition,
                        systemImage:
                            "arrow.right"
                    )
                )
            }
        }

        return result
    }

    private var restFlowCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Rest & flow",
                            norwegian:
                                "Pause & flyt"
                        )
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Actual rest recorded during this workout.",
                            norwegian:
                                "Faktisk pause registrert under denne økta."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "stopwatch.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 8
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 8
                    )
                ],
                spacing: 8
            ) {
                restMetricTile(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Total rest",
                            norwegian:
                                "Total pause"
                        ),
                    value:
                        compactStrengthDuration(
                            totalRestSeconds
                        ),
                    icon:
                        "pause.circle.fill"
                )

                restMetricTile(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Average rest",
                            norwegian:
                                "Snittpause"
                        ),
                    value:
                        compactStrengthDuration(
                            averageRestSeconds
                        ),
                    icon:
                        "timer"
                )

                restMetricTile(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Longest rest",
                            norwegian:
                                "Lengste pause"
                        ),
                    value:
                        compactStrengthDuration(
                            longestRestSeconds
                        ),
                    icon:
                        "hourglass"
                )

                restMetricTile(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Exercise changes",
                            norwegian:
                                "Mellom øvelser"
                        ),
                    value:
                        totalTransitionSeconds >
                            0
                            ? compactStrengthDuration(
                                totalTransitionSeconds
                            )
                            : "—",
                    icon:
                        "arrow.left.arrow.right"
                )
            }

            if !restTimeline.isEmpty {
                Divider()
                    .opacity(0.55)

                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            restTimeline
                                .prefix(8)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) {
                        index,
                        entry in

                        HStack(spacing: 10) {
                            Image(
                                systemName:
                                    entry
                                        .systemImage
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .frame(
                                width: 26,
                                height: 26
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Circle()
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    entry.title
                                )
                                .font(
                                    .caption
                                        .weight(
                                            .semibold
                                        )
                                )
                                .lineLimit(1)

                                if let subtitle =
                                        entry.subtitle {
                                    Text(
                                        subtitle
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }
                            }

                            Spacer()

                            Text(
                                compactStrengthDuration(
                                    entry.seconds
                                )
                            )
                            .font(
                                .caption
                                    .weight(.bold)
                            )
                            .monospacedDigit()
                        }
                        .padding(
                            .vertical,
                            8
                        )

                        if index <
                            min(
                                restTimeline.count,
                                8
                            ) - 1 {
                            Divider()
                                .opacity(0.42)
                        }
                    }
                }

                if restTimeline.count > 8 {
                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "+ %d more recorded pauses",
                            norwegian:
                                "+ %d flere registrerte pauser",
                            restTimeline.count - 8
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.card,
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
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    private func restMetricTile(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: icon
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 30,
                height: 30
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(value)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(10)
        .background(
            ATHLTHTheme
                .surfaceStone
                .opacity(0.62),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }

    private var exerciseBreakdownSection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Exercises",
                            norwegian:
                                "Øvelser"
                        )
                    )
                    .font(
                        .title3.weight(
                            .bold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "What you actually completed",
                            norwegian:
                                "Det du faktisk gjennomførte"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            if let strengthWorkout =
                    resolvedStrengthWorkout,
               !strengthWorkout
                    .exercises
                    .isEmpty {
                ForEach(
                    strengthWorkout
                        .exercises
                ) { exercise in
                    exerciseDetailCard(
                        exercise
                    )
                }
            } else {
                ATHLTHCard {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "No exercise breakdown is available for this workout.",
                            norwegian:
                                "Ingen øvelsesdetaljer er tilgjengelige for denne økta."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }
        }
    }

    private func exerciseDetailCard(
        _ exercise:
            StrengthExerciseLog
    ) -> some View {
        let summary =
            muscleSummary.exercises
                .first {
                    $0.id ==
                        exercise.id
                }
        let completedSets =
            exercise.sets
                .filter(
                    \.isCompleted
                )
        let exerciseRecords =
            workoutPersonalRecords
                .filter {
                    $0.exerciseID ==
                        exercise.id
                }

        return VStack(
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
                    Text(
                        exercise.exercise
                            .displayName
                    )
                    .font(
                        .headline.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    if let summary {
                        Text(
                            exerciseMetricText(
                                summary
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }

                Spacer()

                if !exerciseRecords.isEmpty {
                    Label(
                        "PR",
                        systemImage:
                            "trophy.fill"
                    )
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
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
                            .premiumGold
                            .opacity(0.12),
                        in: Capsule()
                    )
                }
            }

            if let summary {
                muscleChipRow(
                    primary:
                        summary
                            .primaryMuscles,
                    secondary:
                        summary
                            .secondaryMuscles
                )
            }

            if completedSets.isEmpty {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "No completed sets recorded.",
                        norwegian:
                            "Ingen fullførte sett registrert."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            completedSets
                                .enumerated()
                        ),
                        id: \.element.id
                    ) {
                        index,
                        set in

                        Button {
                            guard
                                editableStrengthWorkout !=
                                    nil
                            else {
                                return
                            }

                            editingSetResult =
                                StrengthSetResultEditTarget(
                                    exerciseID:
                                        exercise.id,
                                    exerciseName:
                                        exercise
                                            .exercise
                                            .name,
                                    exercise:
                                        exercise
                                            .exercise,
                                    set: set
                                )
                        } label: {
                            HStack(spacing: 10) {
                                Text(
                                    "\(set.setNumber)"
                                )
                                .font(
                                    .caption
                                        .weight(
                                            .bold
                                        )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .accentDeep
                                )
                                .frame(
                                    width: 28,
                                    height: 28
                                )
                                .background(
                                    ATHLTHTheme
                                        .accentSoft,
                                    in: Circle()
                                )

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        historySetSummary(
                                            set
                                        )
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
                                    .lineLimit(2)

                                    if let rest =
                                            set
                                                .actualRestAfterSeconds,
                                       rest > 0 {
                                        Label(
                                            ATHLTHLocalization.format(
                                                english:
                                                    "Rest %@",
                                                norwegian:
                                                    "Pause %@",
                                                compactStrengthDuration(
                                                    rest
                                                )
                                            ),
                                            systemImage:
                                                "pause.fill"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                    }
                                }

                                Spacer()

                                if exerciseRecords
                                    .contains(
                                        where: {
                                            $0.setID ==
                                                set.id
                                        }
                                    ) {
                                    Image(
                                        systemName:
                                            "trophy.fill"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .premiumGold
                                    )
                                }

                                if editableStrengthWorkout !=
                                    nil {
                                    Image(
                                        systemName:
                                            "pencil"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .accentDeep
                                    )
                                }
                            }
                            .padding(
                                .vertical,
                                10
                            )
                            .contentShape(
                                Rectangle()
                            )
                        }
                        .buttonStyle(.plain)

                        if index <
                            completedSets.count - 1 {
                            Divider()
                                .opacity(0.42)
                        }
                    }
                }
                .padding(
                    .horizontal,
                    10
                )
                .background(
                    ATHLTHTheme
                        .surfaceStone
                        .opacity(0.62),
                    in:
                        RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                )
            }

            if let transition =
                    exercise
                        .transitionToNextExerciseSeconds,
               transition > 0 {
                Label(
                    ATHLTHLocalization.format(
                        english:
                            "Change to next exercise · %@",
                        norwegian:
                            "Bytte til neste øvelse · %@",
                        compactStrengthDuration(
                            transition
                        )
                    ),
                    systemImage:
                        "arrow.right"
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.card,
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
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private func muscleChipRow(
        primary: [String],
        secondary: [String]
    ) -> some View {
        let primaryNames =
            primary
                .map(displayMuscleName)
        let secondaryNames =
            secondary
                .map(displayMuscleName)

        if !primaryNames.isEmpty ||
            !secondaryNames.isEmpty {
            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 7) {
                    ForEach(
                        Array(
                            primaryNames
                                .prefix(3)
                        ),
                        id: \.self
                    ) { muscle in
                        muscleChip(
                            muscle,
                            primary: true
                        )
                    }

                    ForEach(
                        Array(
                            secondaryNames
                                .prefix(3)
                        ),
                        id: \.self
                    ) { muscle in
                        muscleChip(
                            muscle,
                            primary: false
                        )
                    }
                }
            }
        }
    }

    private func muscleChip(
        _ text: String,
        primary: Bool
    ) -> some View {
        Text(text)
            .font(
                .caption2.weight(
                    primary
                        ? .semibold
                        : .regular
                )
            )
            .foregroundStyle(
                primary
                    ? ATHLTHTheme
                        .accentDeep
                    : ATHLTHTheme
                        .mutedText
            )
            .padding(
                .horizontal,
                9
            )
            .padding(
                .vertical,
                6
            )
            .background(
                primary
                    ? ATHLTHTheme
                        .accentSoft
                    : ATHLTHTheme
                        .surfaceStone,
                in: Capsule()
            )
    }

    private var workoutPersonalRecords:
        [StrengthWorkoutPersonalRecord] {
        guard let workout =
                resolvedStrengthWorkout
        else {
            return []
        }

        return strength
            .workoutPersonalRecords(
                for: workout
            )
    }

    private var performanceCard:
        some View {
        ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Performance",
                            norwegian:
                                "Prestasjon"
                        )
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Progress compared with earlier sessions",
                            norwegian:
                                "Fremgang mot tidligere økter"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "trophy.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
            }

            VStack(spacing: 0) {
                ForEach(
                    Array(
                        workoutPersonalRecords
                            .prefix(4)
                            .enumerated()
                    ),
                    id: \.element.id
                ) {
                    index,
                    record in

                    HStack(spacing: 10) {
                        Image(
                            systemName:
                                "arrow.up.right"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
                        .frame(
                            width: 28,
                            height: 28
                        )
                        .background(
                            ATHLTHTheme
                                .premiumGold
                                .opacity(0.10),
                            in: Circle()
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                record.exerciseName
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Text(
                                "\(record.previousValue) → \(record.value)"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        Spacer()

                        Text(
                            ATHLTHLocalization.choose(
                                english: "New PR",
                                norwegian: "Ny PR"
                            )
                        )
                        .font(
                            .caption2.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
                    }
                    .padding(
                        .vertical,
                        9
                    )

                    if index <
                        min(
                            workoutPersonalRecords
                                .count,
                            4
                        ) - 1 {
                        Divider()
                            .opacity(0.42)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var hasHealthMetrics: Bool {
        guard let metrics =
                resolvedStrengthWorkout?
                    .healthMetrics
        else {
            return workout
                .activeEnergyKilocalories
                .map { $0 > 0 } ??
                false
        }

        return (
            metrics.averageHeartRate ??
            0
        ) > 0 ||
        (
            metrics.maxHeartRate ??
            0
        ) > 0 ||
        (
            metrics.activeCalories ??
            workout
                .activeEnergyKilocalories ??
            0
        ) > 0
    }

    private var healthMetricsCard:
        some View {
        let metrics =
            resolvedStrengthWorkout?
                .healthMetrics
        let calories =
            metrics?
                .activeCalories ??
            workout
                .activeEnergyKilocalories

        return ATHLTHCard {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Heart & effort",
                        norwegian:
                            "Puls & belastning"
                    )
                )
                .font(
                    .headline.weight(
                        .semibold
                    )
                )

                Spacer()

                Image(
                    systemName:
                        "heart.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 8
            ) {
                if let average =
                        metrics?
                            .averageHeartRate,
                   average > 0 {
                    healthMetricTile(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Average HR",
                                norwegian:
                                    "Snittpuls"
                            ),
                        value:
                            "\(Int(average.rounded()))",
                        suffix: "bpm"
                    )
                }

                if let maximum =
                        metrics?
                            .maxHeartRate,
                   maximum > 0 {
                    healthMetricTile(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Max HR",
                                norwegian:
                                    "Makspuls"
                            ),
                        value:
                            "\(Int(maximum.rounded()))",
                        suffix: "bpm"
                    )
                }

                if let calories,
                   calories > 0 {
                    healthMetricTile(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Energy",
                                norwegian:
                                    "Energi"
                            ),
                        value:
                            "\(Int(calories.rounded()))",
                        suffix: "kcal"
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    private func healthMetricTile(
        title: String,
        value: String,
        suffix: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            HStack(
                alignment:
                    .firstTextBaseline,
                spacing: 3
            ) {
                Text(value)
                    .font(
                        .title3.weight(
                            .bold
                        )
                    )
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 58,
            alignment: .leading
        )
        .padding(10)
        .background(
            ATHLTHTheme
                .surfaceStone
                .opacity(0.62),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }

    private var repsText: String {
        let reps =
            resolvedStrengthWorkout?
                .totalCompletedReps ??
            muscleSummary
                .totalReps

        return reps > 0
            ? "\(reps)"
            : "—"
    }

    private var restSummaryText: String {
        totalRestSeconds > 0
            ? compactStrengthDuration(
                totalRestSeconds
            )
            : "—"
    }

    private func compactStrengthDuration(
        _ seconds: TimeInterval
    ) -> String {
        guard seconds > 0 else {
            return "—"
        }

        let total =
            max(
                Int(
                    seconds.rounded()
                ),
                1
            )
        let hours =
            total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainingSeconds =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remainingSeconds
            )
        }

        return String(
            format:
                "%d:%02d",
            minutes,
            remainingSeconds
        )
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

    private var setResultsCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Set details",
                            norwegian: "Settdetaljer"
                        )
                    )
                    .font(.headline.weight(.semibold))

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Tap a completed set to correct reps, load or machine result.",
                            norwegian:
                                "Trykk på et fullført sett for å rette repetisjoner, belastning eller maskinresultat."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            if let strengthWorkout =
                    editableStrengthWorkout {
                ForEach(
                    Array(
                        strengthWorkout
                            .exercises
                            .enumerated()
                    ),
                    id: \.element.id
                ) {
                    exerciseIndex,
                    exercise in

                    if exerciseIndex > 0 {
                        Divider()
                            .opacity(0.55)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        Text(
                            exercise.exercise.name
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        ForEach(
                            exercise.sets.filter(
                                \.isCompleted
                            )
                        ) { set in
                            Button {
                                editingSetResult =
                                    StrengthSetResultEditTarget(
                                        exerciseID:
                                            exercise.id,
                                        exerciseName:
                                            exercise
                                                .exercise
                                                .name,
                                        exercise:
                                            exercise.exercise,
                                        set: set
                                    )
                            } label: {
                                HStack(spacing: 10) {
                                    Text(
                                        "\(set.setNumber)"
                                    )
                                    .font(
                                        .caption
                                            .weight(.bold)
                                    )
                                    .frame(
                                        width: 26,
                                        height: 26
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .accentSoft,
                                        in: Circle()
                                    )

                                    Text(
                                        historySetSummary(
                                            set
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )

                                    Spacer()

                                    Image(
                                        systemName:
                                            "pencil"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .accentDeep
                                    )
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.card,
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
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
    }

    private func historySetSummary(
        _ set: StrengthSetLog
    ) -> String {
        if let segments =
                set.effortSegments,
           segments.count > 1 {
            let parts =
                segments.compactMap {
                    segment -> String? in

                    if let reps =
                            segment.reps,
                       let weight =
                            segment.weightKilograms {
                        return String(
                            format:
                                "%d × %.1f kg",
                            reps,
                            weight
                        )
                    }

                    if let reps =
                            segment.reps,
                       let resistance =
                            segment.resistanceLevel {
                        return
                            "\(reps) × " +
                            ATHLTHLocalization.choose(
                                english:
                                    "level \(resistance)",
                                norwegian:
                                    "steg \(resistance)"
                            )
                    }

                    if let duration =
                            segment.durationSeconds {
                        return
                            formatSetDuration(
                                seconds:
                                    TimeInterval(
                                        duration
                                    )
                            )
                    }

                    return nil
                }

            if !parts.isEmpty {
                return parts.joined(
                    separator: " + "
                )
            }
        }

        var parts: [String] = []

        if let duration =
                set.resolvedCompletedDurationSeconds {
            parts.append(
                formatSetDuration(
                    seconds:
                        TimeInterval(duration)
                )
            )
        } else if let reps =
                    set.resolvedCompletedReps {
            parts.append("\(reps) reps")
        }

        if set.resolvedLoadKind ==
            .resistanceLevel,
           let level =
                set.completedResistanceLevel {
            parts.append(
                ATHLTHLocalization.choose(
                    english:
                        "level \(level)",
                    norwegian:
                        "steg \(level)"
                )
            )
        } else if let weight =
                    set.completedWeightKilograms {
            parts.append(
                String(
                    format:
                        "%.1f kg",
                    weight
                )
            )
        }

        if let distance =
                set.resolvedCompletedDistanceMeters,
           distance > 0 {
            parts.append(
                String(
                    format:
                        "%.0f m",
                    distance
                )
            )
        }

        return parts.isEmpty
            ? ATHLTHLocalization.choose(
                english: "Completed",
                norwegian: "Fullført"
            )
            : parts.joined(
                separator: " · "
            )
    }

    private func formatSetDuration(
        seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )

        if total >= 3_600 {
            return String(
                format:
                    "%d:%02d:%02d",
                total / 3_600,
                (total % 3_600) / 60,
                total % 60
            )
        }

        return String(
            format:
                "%02d:%02d",
            total / 60,
            total % 60
        )
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
              resolvedStrengthWorkout != nil
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
                    resolvedStrengthWorkout?
                        .healthMetrics
                        .averageHeartRate,
                maxHeartRateBPM:
                    resolvedStrengthWorkout?
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

        if resolvedStrengthWorkout == nil {
            return
                "Detailed strength data is not available for this workout."
        }

        return
            "Coach insight is not available for this workout yet."
    }
}
