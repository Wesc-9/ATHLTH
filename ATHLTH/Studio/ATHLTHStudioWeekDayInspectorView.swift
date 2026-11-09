import SwiftUI

/// A day in the Home week strip opens in the existing right-hand iPad
/// inspector, without moving the week strip or fabricating workout history.
enum ATHLTHStudioWeekDayInspectorPolicy {
    static func canStart(
        _ item: ATHLTHStudioSchedule.Occurrence,
        completed: Bool,
        skipped: Bool
    ) -> Bool {
        item.planID != nil && !item.workout.isExplicitRestDay &&
            !completed && !skipped
    }
}

struct ATHLTHStudioWeekDayInspectorView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let date: Date
    let onOpenWorkout: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onStartWorkout: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onSendToWatch: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onInspectRecorded: (WorkoutSummary) -> Void
    let onPlanWorkout: (Date) -> Void

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let canvas = ATHLTHStudioStyle.canvas
    private let outline = ATHLTHStudioStyle.outline

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var selectedDay: ATHLTHStudioHomeWeek.Day? {
        ATHLTHStudioHomeWeek.make(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            recorded: ATHLTHStudioRecordedWorkouts.merged(
                health: health.healthDataAvailable &&
                    health.hasRequestedAuthorization ? health.workouts : [],
                localStrength: strength.workoutHistory
            ),
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: date
        ).days.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dateHeading

                if let selectedDay {
                    if selectedDay.planned.isEmpty &&
                        selectedDay.recorded.isEmpty &&
                        selectedDay.restDays.isEmpty {
                        emptyDay
                    } else {
                        if !selectedDay.planned.isEmpty {
                            sectionTitle(tr("Planned workouts", "Planlagte økter"))
                            ForEach(selectedDay.planned) { item in
                                plannedCard(item)
                            }
                        }

                        if !selectedDay.restDays.isEmpty {
                            sectionTitle(tr("Rest days", "Hviledager"))
                            ForEach(selectedDay.restDays) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: "moon.zzz")
                                        .font(.title3)
                                        .foregroundStyle(gold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.workout.title.isEmpty
                                            ? tr("Rest day", "Hviledag")
                                            : item.workout.title)
                                            .font(.headline)
                                            .foregroundStyle(ink)
                                        if let name = item.planTitle {
                                            Text(name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(15)
                                .background(.white, in:
                                    RoundedRectangle(cornerRadius: 15)
                                )
                            }
                        }

                        if !selectedDay.recorded.isEmpty {
                            sectionTitle(tr("Recorded workouts", "Registrerte økter"))
                            ForEach(selectedDay.recorded) { recorded in
                                recordedRow(recorded)
                            }
                        }
                    }

                    if selectedDay.planned.isEmpty &&
                        selectedDay.restDays.isEmpty &&
                        HomeWeeklyProgressCalendar.canScheduleStandalone(on: date) {
                        Button {
                            onPlanWorkout(Calendar.current.startOfDay(for: date))
                        } label: {
                            Label(tr("Plan workout", "Planlegg økt"), systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ink)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(canvas.ignoresSafeArea())
        .accessibilityIdentifier("athlth-ipad-week-day-inspector")
    }

    private var dateHeading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("WEEKLY PLAN", "UKESPLAN"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.7)
                .foregroundStyle(gold)

            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

            if let day = selectedDay {
                HStack(spacing: 14) {
                    Label(
                        "\(day.planned.count) " + tr("planned", "planlagte"),
                        systemImage: "calendar"
                    )
                    Label(
                        "\(day.recorded.count) " + tr("recorded", "registrerte"),
                        systemImage: "checkmark.circle"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { outline.opacity(0.75).frame(height: 1) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
    }

    private func plannedCard(
        _ item: ATHLTHStudioSchedule.Occurrence
    ) -> some View {
        let done = completed(item)
        let skipped = item.planID.map {
            session.isPlanSessionSkipped(
                planID: $0, sessionID: item.workout.id
            )
        } ?? false
        let canStart = ATHLTHStudioWeekDayInspectorPolicy.canStart(
            item, completed: done, skipped: skipped
        )

        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: item.workout.kind.systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(gold)
                    .frame(width: 40, height: 40)
                    .background(gold.opacity(0.09), in:
                        RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.workout.title)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.planTitle ?? tr(
                        "Independent workout", "Frittstående økt"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Label(
                done ? tr("Completed", "Fullført") :
                    skipped ? tr("Skipped", "Hoppet over") :
                    tr("Scheduled", "Planlagt"),
                systemImage: done ? "checkmark.circle.fill" :
                    skipped ? "minus.circle" : "calendar"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(done ? Color.green : ink.opacity(0.66))

            HStack(spacing: 7) {
                metric(
                    tr("Duration", "Varighet"),
                    item.workout.durationMinutes.map { "\($0) min" } ?? "—",
                    "clock"
                )
                if let distance = item.workout.targetDistanceKilometers,
                   distance > 0 {
                    metric(
                        tr("Distance", "Distanse"),
                        String(format: "%.1f km", distance),
                        "point.bottomleft.forward.to.point.topright.scurvepath"
                    )
                }
                if let pace = item.workout.targetPaceSecondsPerKilometer,
                   pace > 0 {
                    let seconds = Int(pace.rounded())
                    metric(
                        tr("Target pace", "Måltempo"),
                        String(format: "%d:%02d", seconds / 60, seconds % 60),
                        "speedometer"
                    )
                }
            }

            if !item.workout.resolvedWorkoutBlocks.isEmpty ||
                !item.workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Text(tr("Workout structure", "Øktens oppbygning"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)

                    ForEach(
                        Array(item.workout.resolvedWorkoutBlocks.prefix(10).enumerated()),
                        id: \.offset
                    ) { index, block in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(index == 0 ? gold : outline)
                                .frame(width: 7, height: 7)
                                .padding(.top, 6)
                            Text(block.title)
                                .font(.subheadline)
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(item.workout.exercises) { exercise in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "dumbbell")
                                .font(.caption)
                                .foregroundStyle(gold)
                                .frame(width: 12)
                            Text(exercise.embeddedExercise.displayName)
                                .font(.subheadline)
                                .foregroundStyle(ink)
                            Spacer(minLength: 4)
                            Text("\(exercise.sets) " + tr("sets", "sett"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if item.workout.resolvedWorkoutBlocks.count > 10 {
                        Text(tr("See the workout for all steps.",
                                "Åpne økten for å se alle delene."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(canvas, in: RoundedRectangle(cornerRadius: 14))
            }

            if let note = item.workout.notes, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if canStart {
                    Button {
                        onStartWorkout(item)
                    } label: {
                        Label(tr("Start workout", "Start økt"),
                              systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
                }

                Button {
                    onOpenWorkout(item)
                } label: {
                    Label(tr("Workout details", "Se økt"),
                          systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ink)
            }

            if canStart && [.running, .walking, .strength].contains(
                item.workout.kind
            ) {
                Button {
                    onSendToWatch(item)
                } label: {
                    Label(tr("Send to Apple Watch", "Send til Apple Watch"),
                          systemImage: "applewatch")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(gold)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(outline.opacity(0.9), lineWidth: 1)
        }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(gold)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(canvas, in: RoundedRectangle(cornerRadius: 12))
    }

    private func recordedRow(_ workout: WorkoutSummary) -> some View {
        Button {
            onInspectRecorded(workout)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.activity.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(workout.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Text("\(Int(workout.duration / 60)) min")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Inspect the recorded workout", "Åpne registrert økt"))
    }

    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(gold)
            Text(tr("No workouts this day", "Ingen økter denne dagen"))
                .font(.headline)
                .foregroundStyle(ink)
            Text(tr(
                "No workouts are scheduled or recorded for this date.",
                "Ingen økter er planlagt eller registrert denne datoen."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func completed(_ item: ATHLTHStudioSchedule.Occurrence) -> Bool {
        guard let planID = item.planID else { return false }
        return session.isPlanSessionCompleted(
            planID: planID,
            sessionID: item.workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }
}
