import Foundation
import SwiftUI

/// Editorial, evidence-backed results for a finished strength session.
/// The review is read-only; training history and the Save & Share flow are
/// owned by PostWorkoutReviewView.
struct ATHLTHPostStrengthReview: View {
    let workout: SocialPublishableWorkout
    let strengthLog: StrengthWorkoutLog?
    let muscleProfile: StrengthMuscleProfile
    let personalRecords: [StrengthWorkoutPersonalRecord]

    private let ink = Color(red: 0.16, green: 0.18, blue: 0.21)
    private let muted = Color(red: 0.46, green: 0.47, blue: 0.49)
    private let bronze = Color(red: 0.59, green: 0.44, blue: 0.28)
    private let surface = Color.white
    private let line = Color(red: 0.89, green: 0.89, blue: 0.88)
    private let pale = Color(red: 0.964, green: 0.961, blue: 0.954)

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            hero
            metrics

            if !personalRecords.isEmpty {
                recordsCard
            }
            if hasCardio {
                cardioCard
            }

            exercisesCard

            if !muscleProfile.topActivations.isEmpty {
                focusCard
            }
            if hasHealthOrRestData {
                recoveryCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("athlth-strength-postworkout-premium")
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image("StrengthPostWorkoutHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }

            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.25),
                    Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 11) {
                Label(
                    tr("WORKOUT COMPLETED", "ØKT FULLFØRT"),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Color.white.opacity(0.91))

                Spacer(minLength: 4)

                Text(tr("Your training. In detail.", "Økten din. I detalj."))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.83))
            }
            .padding(23)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var completedSets: Int? {
        if let strengthLog { return strengthLog.totalCompletedSets }
        return nil
    }

    private var exerciseCount: Int {
        if let strengthLog {
            return strengthLog.exercises.filter {
                $0.isCompleted || $0.sets.contains(where: \.isCompleted)
            }.count
        }
        return workout.strengthExerciseCount ?? 0
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(
                tr("THE WORKOUT IN NUMBERS", "ØKTEN I TALL"),
                subtitle: tr("Only what was actually recorded", "Bare faktisk registrerte resultater")
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                metric(
                    tr("Duration", "Varighet"),
                    value: durationLabel(workout.duration),
                    symbol: "clock"
                )
                metric(
                    tr("Exercises", "Øvelser"),
                    value: "\(exerciseCount)",
                    symbol: "figure.strengthtraining.traditional"
                )
                metric(
                    tr("Completed sets", "Fullførte sett"),
                    value: completedSets.map(String.init) ?? "—",
                    symbol: "checkmark.square.stack"
                )
                metric(
                    tr("Training volume", "Treningsvolum"),
                    value: volumeLabel,
                    symbol: "scalemass"
                )
            }
        }
    }

    private var volumeLabel: String {
        let volume = workout.strengthTotalVolumeKilograms
            ?? strengthLog?.totalVolumeKilograms
        guard let volume, volume.isFinite, volume > 0 else { return "—" }
        return volume >= 1000
            ? String(format: "%.1f t", volume / 1000)
            : String(format: "%.0f kg", volume)
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(bronze)

            VStack(alignment: .leading, spacing: 5) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.77)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(18)
        .background(surface, in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(line, lineWidth: 0.7))
        .accessibilityElement(children: .combine)
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "trophy")
                    .font(.title2)
                    .foregroundStyle(bronze)
                    .frame(width: 44, height: 44)
                    .background(pale, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("PERSONAL BESTS", "PERSONLIGE REKORDER"))
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(muted)
                    Text(tr("Progress worth remembering", "Fremgang å ta med seg"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
                Text("\(personalRecords.count)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(bronze)
            }

            ForEach(Array(personalRecords.prefix(4)), id: \.id) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(
                        tr("Now", "Nå") + ": " + record.value + "   ·   " +
                        tr("Previously", "Tidligere") + ": " + record.previousValue
                    )
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if record.id != personalRecords.prefix(4).last?.id {
                    Divider().overlay(line)
                }
            }
        }
        .padding(20)
        .background(surface, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(line, lineWidth: 0.7))
    }

    private var hasCardio: Bool {
        (workout.strengthCardioExerciseCount ?? 0) > 0 ||
        (strengthLog?.exercises.contains {
            StrengthCardioExercisePolicy.isCardio($0.exercise.name) &&
            $0.sets.contains(where: \.isCompleted)
        } ?? false)
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(ink)
                    .frame(width: 46, height: 46)
                    .background(pale, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("CONDITIONING", "KONDISJON"))
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(muted)
                    Text(tr("Within your strength workout", "Som del av styrkeøkten"))
                        .font(.headline)
                        .foregroundStyle(ink)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(workout.strengthCardioDurationSeconds.map {
                    durationLabel(TimeInterval($0))
                } ?? "—")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                Spacer(minLength: 4)
                if let count = workout.strengthCardioExerciseCount {
                    Text(tr("\(count) cardio exercises", "\(count) kondisjonsøvelser"))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
            }

            Text(tr(
                "Conditioning contributes to workout time, but not lifting volume or strength records.",
                "Kondisjon inngår i øktens varighet, men ikke løftevolum eller styrkerekorder."
            ))
            .font(.caption)
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(surface, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(line, lineWidth: 0.7))
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(
                tr("YOUR EXERCISES", "ØVELSENE DINE"),
                subtitle: tr("Completed work, not planned or skipped sets",
                             "Gjennomført arbeid, ikke planlagte eller hoppede sett")
            )

            VStack(alignment: .leading, spacing: 0) {
                if let strengthLog {
                    let entries = strengthLog.exercises.filter {
                        ($0.isCompleted || $0.sets.contains(where: \.isCompleted)) &&
                        !StrengthCardioExercisePolicy.isCardio($0.exercise.name)
                    }
                    if entries.isEmpty {
                        emptyExercises
                    } else {
                        ForEach(entries.indices, id: \.self) { index in
                            exerciseRow(entries[index], index: index + 1)
                            if index < entries.count - 1 {
                                Divider().overlay(line).padding(.leading, 49)
                            }
                        }
                    }
                } else if let summaries = workout.strengthPerformedExerciseSummaries,
                          !summaries.isEmpty {
                    ForEach(summaries.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            exerciseNumber(index + 1)
                            Text(summaries[index])
                                .font(.subheadline)
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                        if index < summaries.count - 1 {
                            Divider().overlay(line).padding(.leading, 49)
                        }
                    }
                } else {
                    emptyExercises
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 5)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(line, lineWidth: 0.7))
        }
    }

    private var emptyExercises: some View {
        Text(tr(
            "A detailed set log is not available for this workout.",
            "Detaljert settlogg er ikke tilgjengelig for denne økten."
        ))
        .font(.subheadline)
        .foregroundStyle(muted)
        .padding(.vertical, 18)
    }

    private func exerciseNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(ink)
            .frame(width: 36, height: 36)
            .background(pale, in: RoundedRectangle(cornerRadius: 11))
    }

    private func exerciseRow(_ entry: StrengthExerciseLog, index: Int) -> some View {
        let sets = entry.sets.filter(\.isCompleted)
        let isTimeOnly = entry.exercise.isTimeOnlyBodyweightStrength ||
            sets.contains(where: { $0.resolvedTargetKind == .time })
        let timeSeconds = sets.compactMap {
            $0.resolvedCompletedDurationSeconds ??
            $0.actualSetElapsedSeconds.map { Int($0.rounded()) }
        }.reduce(0, +)
        let reps = sets.compactMap(\.resolvedCompletedReps).reduce(0, +)
        let maxWeight = entry.exercise.isTimeOnlyBodyweightStrength
            ? nil : sets.filter {
                $0.recordsWeight != false &&
                $0.resolvedTargetKind != .time &&
                $0.resolvedLoadKind == .weightKilograms
            }.compactMap(\.completedWeightKilograms).filter { $0 > 0 }.max()

        return HStack(alignment: .top, spacing: 12) {
            exerciseNumber(index)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Text("\(sets.count) " + tr("sets", "sett"))
                    if isTimeOnly {
                        Text("·")
                        Text(timeSeconds > 0
                            ? durationLabel(TimeInterval(timeSeconds))
                            : tr("Time not recorded", "Tid ikke registrert"))
                    } else if reps > 0 {
                        Text("·")
                        Text("\(reps) reps")
                    }
                }
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)

            if let maxWeight {
                Text(String(format: "%.1f kg", maxWeight))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.77)
            } else if isTimeOnly {
                Image(systemName: "timer")
                    .font(.subheadline)
                    .foregroundStyle(bronze)
                    .accessibilityLabel(tr("Time-based exercise", "Tidsbasert øvelse"))
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(
                tr("MUSCLE FOCUS", "MUSKELFOKUS"),
                subtitle: tr("Estimated from completed exercises",
                             "Anslått ut fra registrerte øvelser")
            )
            VStack(alignment: .leading, spacing: 13) {
                ForEach(Array(muscleProfile.topActivations.prefix(3))) { activation in
                    let intensity = muscleProfile.intensity(for: activation.region)
                    HStack(spacing: 12) {
                        Text(activation.region.activityDisplayTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(pale)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(bronze.opacity(0.83))
                                        .frame(width: max(0, geo.size.width * intensity))
                                }
                        }
                        .frame(width: 106, height: 7)
                        .accessibilityHidden(true)
                    }
                }
            }
            .padding(19)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(line, lineWidth: 0.7))
        }
    }

    private var hasHealthOrRestData: Bool {
        (strengthLog?.totalActualRestSeconds ?? 0) > 0 ||
        (workout.strengthWorkoutAverageHeartRateBPM ?? 0) > 0 ||
        (workout.activeEnergyKilocalories ?? 0) > 0
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(
                tr("WORKOUT SIGNALS", "SIGNALER FRA ØKTEN"),
                subtitle: tr("Recorded data, not a recovery prediction",
                             "Registrerte tall, ikke anslått restitusjon")
            )
            VStack(spacing: 0) {
                if let bpm = workout.strengthWorkoutAverageHeartRateBPM,
                   bpm.isFinite, bpm > 0 {
                    signal(
                        tr("Average heart rate", "Snittpuls"),
                        value: "\(Int(bpm.rounded())) bpm",
                        icon: "heart"
                    )
                }
                if let energy = workout.activeEnergyKilocalories,
                   energy.isFinite, energy > 0 {
                    signal(
                        tr("Active energy", "Aktiv energi"),
                        value: "\(Int(energy.rounded())) kcal",
                        icon: "flame"
                    )
                }
                if let rest = strengthLog?.totalActualRestSeconds,
                   rest.isFinite, rest > 0 {
                    signal(
                        tr("Total recorded rest", "Registrert pausetid"),
                        value: durationLabel(rest),
                        icon: "pause"
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(line, lineWidth: 0.7))
        }
    }

    private func signal(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(bronze)
                .frame(width: 26)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ink)
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(ink)
        }
        .padding(.vertical, 12)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.05)
                .foregroundStyle(bronze)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(muted)
        }
        .padding(.horizontal, 2)
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let total = max(Int(duration.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours) " + tr("hr", "t") + " \(minutes) " + tr("min", "min")
        }
        if minutes > 0 {
            return seconds > 0 && minutes < 15
                ? String(format: "%d:%02d min", minutes, seconds)
                : "\(minutes) min"
        }
        return "\(seconds) s"
    }
}
