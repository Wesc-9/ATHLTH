import SwiftUI

/// Focused, read-only review of a completed strength workout. This is not
/// the training editor: all performance values come from completed set logs.
struct ATHLTHStrengthCompletionReview: View {
    let workout: SocialPublishableWorkout
    let log: StrengthWorkoutLog?
    let personalRecords: [StrengthWorkoutPersonalRecord]
    let muscleProfile: StrengthMuscleProfile

    @State private var expandedExerciseIDs: Set<UUID> = []

    private let ink = Color(red: 0.16, green: 0.18, blue: 0.20)
    private let muted = Color(red: 0.43, green: 0.44, blue: 0.45)
    private let border = Color(red: 0.89, green: 0.89, blue: 0.88)
    private let soft = Color(red: 0.96, green: 0.955, blue: 0.947)
    private let bronze = Color(red: 0.60, green: 0.48, blue: 0.33)

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var completedExercises: [StrengthExerciseLog] {
        log?.exercises.filter { $0.sets.contains(where: \.isCompleted) } ?? []
    }

    private var liftingExercises: [StrengthExerciseLog] {
        completedExercises.filter {
            !StrengthCardioExercisePolicy.isCardio($0.exercise.name)
        }
    }

    private var conditioningExercises: [StrengthExerciseLog] {
        completedExercises.filter {
            StrengthCardioExercisePolicy.isCardio($0.exercise.name)
        }
    }

    private var completedCount: Int {
        if let log { return log.totalCompletedSets }
        return 0
    }

    private var totalRest: TimeInterval? {
        guard let log else { return nil }
        let measured = log.exercises.flatMap(\.sets)
            .compactMap(\.actualRestAfterSeconds)
        return measured.isEmpty ? nil : measured.reduce(0, +)
    }

    private var displayVolume: Double? {
        if let log {
            // Historical timed holds may have an obsolete weight field.
            // Never count them toward strength tonnage.
            let measured = log.exercises.reduce(0.0) { sum, item in
                guard !item.exercise.isTimeOnlyBodyweightStrength,
                      !StrengthCardioExercisePolicy.isCardio(item.exercise.name)
                else { return sum }
                return sum + item.sets.filter {
                    $0.recordsWeight != false && $0.resolvedTargetKind == .reps
                }.reduce(0) {
                    $0 + $1.volumeKilograms
                }
            }
            return measured > 0 ? measured : nil
        }
        return workout.strengthTotalVolumeKilograms
    }

    private var heaviestLift: Double? {
        if let log {
            return log.exercises
                .filter {
                    !$0.exercise.isTimeOnlyBodyweightStrength &&
                        !StrengthCardioExercisePolicy.isCardio($0.exercise.name)
                }
                .flatMap(\.sets)
                .filter {
                    $0.countsTowardTrainingLoad &&
                    $0.recordsWeight != false &&
                    $0.resolvedTargetKind == .reps
                }
                .compactMap(\.completedWeightKilograms)
                .filter { $0 > 0 }
                .max()
        }
        return workout.strengthHeaviestWeightKilograms
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            completionHero
            resultsCard
            if !personalRecords.isEmpty { recordsCard }
            if workout.strengthCardioDurationSeconds != nil ||
               !conditioningExercises.isEmpty ||
               workout.strengthCardioExerciseCount != nil {
                cardioCard
            }
            exerciseCard
            if !muscleProfile.topActivations.isEmpty {
                muscleFocusCard
            }
            recoveryCard
        }
        .accessibilityElement(children: .contain)
    }

    private var completionHero: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ZStack(alignment: .bottomLeading) {
                    Image("StrengthPostWorkoutHero")
                    .resizable()
                    .scaledToFill()
                    .athlthBoundedFill()
                    .frame(width: viewport.size.width, height: 190)
                    .clipped()
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("WORKOUT COMPLETE", "ØKT FULLFØRT"),
                          systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.88))
                    Text(workout.title)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(workout.startDate.formatted(
                        date: .abbreviated, time: .shortened
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                }
                .padding(21)
                }
                .frame(width: viewport.size.width, height: 190)
            }
            .frame(height: 190)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 1),
                GridItem(.flexible(), spacing: 1)
            ], spacing: 1) {
                metric(
                    tr("Duration", "Varighet"),
                    duration(workout.duration),
                    "clock"
                )
                metric(
                    tr("Training volume", "Treningsvolum"),
                    displayVolume.map(weight) ?? "—",
                    "scalemass"
                )
                metric(
                    tr("Exercises", "Øvelser"),
                    String(completedExercises.isEmpty
                        ? workout.strengthExerciseCount ?? 0
                        : completedExercises.count),
                    "dumbbell"
                )
                metric(
                    tr("Sets completed", "Gjennomførte sett"),
                    log.map { String($0.totalCompletedSets) } ?? "—",
                    "checkmark.circle"
                )
            }
            .background(soft)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26).stroke(border, lineWidth: 0.8)
        }
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(.horizontal, 19)
        .padding(.vertical, 13)
        .background(.white)
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle(tr("The session at a glance", "Økten i korte trekk"),
                         symbol: "chart.bar.xaxis")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 11),
                GridItem(.flexible(), spacing: 11)
            ], spacing: 11) {
                if let reps = log?.totalCompletedReps, reps > 0 {
                    smallResult(
                        tr("Repetitions", "Repetisjoner"),
                        "\(reps)", "repeat"
                    )
                } else if let reps = workout.strengthTotalReps, reps > 0 {
                    smallResult(
                        tr("Repetitions", "Repetisjoner"),
                        "\(reps)", "repeat"
                    )
                }
                if let heaviestLift {
                    smallResult(
                        tr("Heaviest lift", "Tyngste løft"),
                        String(format: "%.1f kg", heaviestLift),
                        "dumbbell"
                    )
                }
                if let totalRest, totalRest > 0 {
                    smallResult(
                        tr("Time resting", "Tid i pause"),
                        duration(totalRest), "pause.circle"
                    )
                }
            }

            if let groups = workout.strengthMuscleGroups, !groups.isEmpty {
                Divider().overlay(border)
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("Muscle focus", "Muskelgrupper"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                    Text(groups.prefix(5).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .reviewSurface(border: border)
    }

    private func smallResult(_ label: String, _ value: String,
                             _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(bronze)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle(tr("Personal records", "Personlige rekorder"),
                         symbol: "trophy")
            ForEach(Array(personalRecords.prefix(3).enumerated()), id: \.element.id) { index, record in
                HStack(spacing: 13) {
                    Image(systemName: "rosette")
                        .font(.title3)
                        .foregroundStyle(bronze)
                        .frame(width: 40, height: 40)
                        .background(soft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.exerciseName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(record.value)
                            .font(.headline)
                            .foregroundStyle(bronze)
                        if !record.previousValue.isEmpty {
                            Text(tr("Previously", "Tidligere") + ": " + record.previousValue)
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                    }
                    Spacer(minLength: 2)
                }
                if index < min(personalRecords.count, 3) - 1 {
                    Divider().overlay(border)
                }
            }
        }
        .padding(20)
        .reviewSurface(border: border)
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(tr("Conditioning in this workout",
                            "Kondisjon i styrkeøkten"), symbol: "figure.rower")
            HStack(alignment: .firstTextBaseline) {
                Text(
                    workout.strengthCardioDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
                        .map { duration(Double($0)) }
                        ?? "—"
                )
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                Spacer(minLength: 5)
                if let distance = workout.strengthCardioMeasuredMeters, distance > 0 {
                    Text(String(format: "%.2f km", distance / 1_000))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(muted)
                } else if let estimated = workout.strengthCardioEstimatedMeters,
                          estimated > 0 {
                    Text(String(format: "~%.2f km", estimated / 1_000))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(muted)
                }
            }
            if !conditioningExercises.isEmpty {
                Divider().overlay(border)
                ForEach(conditioningExercises) { exercise in
                    let sets = exercise.sets.filter(\.isCompleted)
                    let seconds = sets.compactMap { set -> Int? in
                        if let value = set.resolvedCompletedDurationSeconds, value > 0 {
                            return value
                        }
                        return set.actualSetElapsedSeconds.flatMap {
                            $0.isFinite && $0 > 0 ? Int($0.rounded()) : nil
                        }
                    }.reduce(0, +)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(exercise.exercise.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Spacer(minLength: 4)
                        Text(
                            "\(sets.count) " + tr("sets", "sett") +
                            (seconds > 0 ? " · " + duration(Double(seconds)) : "")
                        )
                        .font(.caption)
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.trailing)
                    }
                }
            }

            Text(tr(
                "Conditioning is shown separately and does not count toward strength tonnage or lifting records.",
                "Kondisjonsdelen vises separat og teller ikke som styrkevolum eller løfterekord."
            ))
            .font(.caption)
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .reviewSurface(border: border)
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(tr("Exercises performed", "Gjennomførte øvelser"),
                         symbol: "list.number")
            if log == nil {
                ForEach(
                    Array((workout.strengthPerformedExerciseSummaries ?? []).enumerated()),
                    id: \.offset
                ) { _, line in
                    Text(safeLegacySummary(line))
                        .font(.subheadline)
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    Divider().overlay(border)
                }
            } else if liftingExercises.isEmpty {
                Text(tr("No lifting exercises were logged.", "Ingen styrkeøvelser ble registrert."))
                    .font(.subheadline)
                    .foregroundStyle(muted)
            } else {
                ForEach(Array(liftingExercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseRow(exercise, number: index + 1)
                    if index < liftingExercises.count - 1 {
                        Divider().overlay(border)
                    }
                }
            }
            Text(tr(
                "Tap an exercise to see the actual result for each set.",
                "Trykk på en øvelse for å se det registrerte resultatet for hvert sett."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(20)
        .reviewSurface(border: border)
    }

    private func exerciseRow(_ exercise: StrengthExerciseLog, number: Int) -> some View {
        let sets = exercise.sets.filter(\.isCompleted)
        let isCardio = StrengthCardioExercisePolicy.isCardio(exercise.exercise.name)
        let isTimed = exercise.exercise.isTimeOnlyBodyweightStrength ||
            sets.contains(where: { $0.resolvedTargetKind == .time })
        let measuredSeconds = sets.compactMap { set -> Int? in
            if let recorded = set.resolvedCompletedDurationSeconds,
               recorded > 0 { return recorded }
            guard isTimed || isCardio,
                  let actual = set.actualSetElapsedSeconds,
                  actual.isFinite, actual > 0 else { return nil }
            return Int(actual.rounded())
        }.reduce(0, +)
        let maxLoad = (!isTimed && !isCardio)
            ? sets.filter {
                $0.countsTowardTrainingLoad &&
                $0.recordsWeight != false &&
                $0.resolvedTargetKind == .reps
            }
            .compactMap(\.completedWeightKilograms).filter { $0 > 0 }.max()
            : nil
        let summary: String = {
            if isTimed {
                return measuredSeconds > 0
                    ? duration(Double(measuredSeconds))
                    : tr("Time not recorded", "Tid ikke registrert")
            }
            if isCardio {
                return measuredSeconds > 0
                    ? duration(Double(measuredSeconds))
                    : tr("Cardio", "Kondisjon")
            }
            if let maxLoad {
                return String(format: "%.1f kg", maxLoad)
            }
            let reps = sets.compactMap(\.resolvedCompletedReps).reduce(0, +)
            return reps > 0 ? "\(reps) " + tr("reps", "reps") : tr("Recorded", "Registrert")
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if !expandedExerciseIDs.insert(exercise.id).inserted {
                        expandedExerciseIDs.remove(exercise.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("\(number)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(bronze)
                        .frame(width: 34, height: 34)
                        .background(soft, in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.exercise.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .multilineTextAlignment(.leading)
                        Text("\(sets.count) " + tr("sets", "sett") + " · " + summary)
                            .font(.caption)
                            .foregroundStyle(muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                        .rotationEffect(.degrees(expandedExerciseIDs.contains(exercise.id) ? 180 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Show recorded sets", "Vis registrerte sett"))

            if expandedExerciseIDs.contains(exercise.id) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sets) { set in
                        HStack(spacing: 9) {
                            Text(tr("Set", "Sett") + " \(set.setNumber)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(muted)
                            Spacer(minLength: 3)
                            Text(setDescription(set, timed: isTimed, cardio: isCardio))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 30)
                    }
                }
                .padding(13)
                .background(soft, in: RoundedRectangle(cornerRadius: 13))
                .transition(.opacity)
            }
        }
    }

    private func setDescription(_ set: StrengthSetLog, timed: Bool, cardio: Bool) -> String {
        if timed || cardio {
            if let seconds = set.resolvedCompletedDurationSeconds, seconds > 0 {
                return duration(Double(seconds))
            }
            if let measured = set.actualSetElapsedSeconds,
               measured.isFinite, measured > 0 {
                return duration(measured)
            }
            return tr("Duration not recorded", "Varighet ikke registrert")
        }
        let reps = set.resolvedCompletedReps
        let weight = set.completedWeightKilograms
        if let reps, let weight, weight > 0, set.countsTowardTrainingLoad,
           set.recordsWeight != false, set.resolvedTargetKind == .reps {
            return "\(reps) " + tr("reps", "reps") +
                String(format: " · %.1f kg", weight)
        }
        if let reps { return "\(reps) " + tr("reps", "reps") }
        return tr("Recorded", "Registrert")
    }

    private var muscleFocusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(tr("Muscle focus", "Muskelbelastning"),
                         symbol: "figure.strengthtraining.traditional")

            HStack(alignment: .center, spacing: 15) {
                StrengthMuscleMapView(
                    profile: muscleProfile,
                    compact: true
                )
                .frame(width: 145, height: 173)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(muscleProfile.topActivations.prefix(3))) { activation in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activation.region.activityDisplayTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(soft)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(bronze)
                                            .frame(
                                                width: max(
                                                    0,
                                                    geometry.size.width *
                                                        muscleProfile.intensity(for: activation.region)
                                                )
                                            )
                                    }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(tr(
                "Relative muscle focus estimated from logged exercises, not a direct physiological measurement.",
                "Relativ muskelbelastning er anslått fra registrerte øvelser, ikke målt direkte i musklene."
            ))
            .font(.caption)
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .reviewSurface(border: border)
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle(tr("Body signals", "Kroppens signaler"), symbol: "heart.text.square")
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                if let pulse = workout.strengthWorkoutAverageHeartRateBPM, pulse > 0 {
                    smallResult(
                        tr("Average heart rate", "Snittpuls"),
                        "\(Int(pulse.rounded())) bpm",
                        "heart"
                    )
                }
                if let kcal = workout.activeEnergyKilocalories, kcal > 0 {
                    smallResult(
                        tr("Active energy", "Aktiv energi"),
                        "\(Int(kcal.rounded())) kcal",
                        "flame"
                    )
                }
                if let skipped = log?.exercises.reduce(0, {
                    $0 + ($1.skippedPlannedSetCount ?? 0)
                }), skipped > 0 {
                    smallResult(tr("Skipped sets", "Hoppede sett"),
                                "\(skipped)", "forward.end")
                }
            }
            if workout.strengthWorkoutAverageHeartRateBPM == nil &&
                workout.activeEnergyKilocalories == nil {
                Text(tr(
                    "No verified pulse or calorie measurements were available for this session.",
                    "Det finnes ingen registrerte pulsmålinger eller kaloridata for denne økten."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            }
        }
        .padding(20)
        .reviewSurface(border: border)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weight(_ value: Double) -> String {
        value >= 1_000
            ? String(format: "%.1f t", value / 1_000)
            : String(format: "%.0f kg", value)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
        }
        if total >= 60 {
            return String(format: "%dm %02ds", total / 60, total % 60)
        }
        return "\(total)s"
    }

    private func safeLegacySummary(_ value: String) -> String {
        // A former time-only hold could carry a historical dummy weight.
        // Keep the original log unchanged, but never present that value as
        // an actual lifting achievement.
        let normalized = value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                       locale: .current)
        guard normalized.contains("six inch hold") ||
              normalized.contains("six inch") else { return value }
        return value.split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.localizedCaseInsensitiveContains("kg") }
            .joined(separator: " · ")
    }
}

private struct ATHLTHStrengthReviewSurface: ViewModifier {
    let border: Color

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 23))
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .stroke(border, lineWidth: 0.8)
            }
    }
}

private extension View {
    func reviewSurface(border: Color) -> some View {
        modifier(ATHLTHStrengthReviewSurface(border: border))
    }
}
