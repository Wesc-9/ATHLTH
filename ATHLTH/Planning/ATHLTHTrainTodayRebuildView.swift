import SwiftUI

/// Phase 1 of Train / I dag. Recording, launch and plan ownership remain in
/// their existing coordinators. This surface only presents real saved sessions.
struct ATHLTHTrainTodayRebuildView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let onOpenSession: (PlannedSession, Bool) -> Void
    let onStartSession: (PlannedSession) -> Void
    let onQuickStart: (WorkoutKind) -> Void
    let onCustomQuick: () -> Void
    let onOpenPlan: () -> Void
    let onOpenGhost: () -> Void

    private var plannedToday: [PlannedSession] {
        guard let plan = session.activePlan else { return [] }
        return TrainingPlanSchedule.sessions(in: plan, on: Date())
    }

    private var standaloneToday: [PlannedSession] {
        session.standalonePlannedSessions(on: Date())
    }

    private var allToday: [(session: PlannedSession, standalone: Bool)] {
        let plan = plannedToday.map { (session: $0, standalone: false) }
        let standalone = standaloneToday.map { (session: $0, standalone: true) }
        return (plan + standalone).sorted {
            ($0.session.scheduledStart ?? .distantFuture) <
                ($1.session.scheduledStart ?? .distantFuture)
        }
    }

    private func recordedStatus(_ workout: PlannedSession) -> String? {
        let logs = strength.workoutHistory.filter {
            $0.plannedSessionID == workout.id && $0.isFinished
        }
        if logs.contains(where: { $0.isFullyCompleted }) {
            return ATHLTHLocalization.choose(
                english: "Completed", norwegian: "Gjennomført"
            )
        }
        if !logs.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Partly completed", norwegian: "Delvis gjennomført"
            )
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            introduction

            if let featured = allToday.first {
                featuredWorkout(featured.session, standalone: featured.standalone)
                if allToday.count > 1 {
                    VStack(alignment: .leading, spacing: 9) {
                        sectionLabel(ATHLTHLocalization.choose(
                            english: "ALSO TODAY", norwegian: "OGSÅ I DAG"
                        ))
                        ForEach(allToday.dropFirst(), id: \.session.id) { item in
                            compactWorkout(item.session, standalone: item.standalone)
                        }
                    }
                }
            } else {
                unscheduledDay
            }

            quickTrain

            HStack(spacing: 9) {
                NavigationLink {
                    ATHLTHProgressView()
                } label: {
                    smallAction(
                        icon: "chart.xyaxis.line",
                        title: ATHLTHLocalization.choose(
                            english: "Progress", norwegian: "Fremgang"
                        )
                    )
                }
                .buttonStyle(.plain)

                Button(action: onOpenGhost) {
                    smallAction(icon: "figure.run.circle", title: "Ghost")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                sectionLabel(ATHLTHLocalization.choose(
                    english: "TODAY", norwegian: "I DAG"
                ))
                Text(ATHLTHLocalization.choose(
                    english: "Make today count.",
                    norwegian: "Din trening. Ditt tempo."
                ))
                .font(.system(size: 27, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .minimumScaleFactor(0.86)
                .lineLimit(2)

                Text(session.activePlan?.title ??
                    ATHLTHLocalization.choose(
                        english: "Train freely or choose a plan",
                        norwegian: "Tren fritt eller velg en plan"
                    ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .center, spacing: 2) {
                Text(Date().formatted(.dateTime.day()))
                    .font(.system(size: 25, weight: .medium, design: .serif))
                Text(Date().formatted(.dateTime.weekday(.abbreviated))
                    .uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
            }
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(width: 64, height: 65)
            .background(
                ATHLTHTheme.champagneSoft,
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
    }

    private func featuredWorkout(
        _ workout: PlannedSession,
        standalone: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "NEXT WORKOUT", norwegian: "DAGENS ØKT"
                    ),
                    systemImage: workout.kind.systemImage
                )
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                Spacer()
                if let status = recordedStatus(workout) {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(workout.title)
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(workoutSubtitle(workout, standalone: standalone))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !workout.exercises.isEmpty {
                HStack(spacing: 6) {
                    ForEach(workout.exercises.prefix(3)) { exercise in
                        Text(exercise.embeddedExercise.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                ATHLTHTheme.champagneSoft,
                                in: Capsule()
                            )
                    }
                }
                .foregroundStyle(ATHLTHTheme.primaryText)
            }

            HStack(spacing: 10) {
                Button {
                    onStartSession(workout)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text(ATHLTHLocalization.choose(
                            english: "Start workout", norwegian: "Start økt"
                        ))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(.white)
                    .background(
                        ATHLTHTheme.accentDeep,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    onOpenSession(workout, standalone)
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Details", norwegian: "Detaljer"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 94, height: 46)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.24), lineWidth: 0.9)
        }
    }

    private func compactWorkout(
        _ workout: PlannedSession,
        standalone: Bool
    ) -> some View {
        Button {
            onOpenSession(workout, standalone)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workout.kind.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(workoutSubtitle(workout, standalone: standalone))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .background(
                Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
    }

    private var unscheduledDay: some View {
        Button(action: onOpenPlan) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.system(size: 21))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "No workout on the calendar",
                        norwegian: "Ingen økt planlagt i dag"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(ATHLTHLocalization.choose(
                        english: "Enjoy a rest day or plan something new.",
                        norwegian: "Ta en hviledag, eller planlegg noe nytt."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(15)
            .frame(maxWidth: .infinity)
            .background(
                Color.white,
                in: RoundedRectangle(cornerRadius: 21)
            )
        }
        .buttonStyle(.plain)
    }

    private var quickTrain: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("QUICK TRAIN")
                    Text(ATHLTHLocalization.choose(
                        english: "Start moving", norwegian: "Tren nå"
                    ))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                }
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Choose iPhone or Watch at start",
                    norwegian: "Velg iPhone eller Watch ved start"
                ))
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 135)
            }
            HStack(spacing: 10) {
                quickButton("Løp", icon: "figure.run", kind: .running)
                quickButton("Gå", icon: "figure.walk", kind: .walking)
                quickButton("Styrke", icon: "dumbbell", kind: .strength)
                Button(action: onCustomQuick) {
                    quickLabel("Egen", icon: "plus")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.88),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func quickButton(
        _ title: String,
        icon: String,
        kind: WorkoutKind
    ) -> some View {
        Button {
            onQuickStart(kind)
        } label: {
            quickLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func quickLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(height: 26)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(
            ATHLTHTheme.champagneSoft.opacity(0.68),
            in: RoundedRectangle(cornerRadius: 15)
        )
    }

    private func smallAction(icon: String, title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(13)
        .background(
            Color.white.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }

    private func workoutSubtitle(
        _ workout: PlannedSession,
        standalone: Bool
    ) -> String {
        var parts: [String] = [workout.kind.title]
        if let date = workout.scheduledStart,
           workout.scheduledTimeIsExplicit != false {
            let hour = Calendar.current.component(.hour, from: date)
            let minute = Calendar.current.component(.minute, from: date)
            if hour != 0 || minute != 0 {
                parts.append(date.formatted(.dateTime.hour().minute()))
            }
        }
        if let minutes = workout.durationMinutes, minutes > 0 {
            parts.append("\(minutes) min")
        }
        if standalone {
            parts.append(ATHLTHLocalization.choose(
                english: "Standalone", norwegian: "Enkeltøkt"
            ))
        }
        return parts.joined(separator: " · ")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.7)
            .foregroundStyle(ATHLTHTheme.accentDeep)
    }
}
