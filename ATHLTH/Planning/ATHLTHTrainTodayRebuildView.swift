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

    private var isPlannedRestDayToday: Bool {
        guard let plan = session.activePlan else { return false }
        return TrainingPlanSchedule.isRestDay(in: plan, on: Date())
    }

    private struct TodayEntry: Identifiable {
        let session: PlannedSession
        let standalone: Bool
        var id: UUID { session.id }
    }

    private var allToday: [TodayEntry] {
        let plan = plannedToday.map { TodayEntry(session: $0, standalone: false) }
        let standalone = standaloneToday.map {
            TodayEntry(session: $0, standalone: true)
        }
        return (plan + standalone).sorted { lhs, rhs in
            let left = sortKey(for: lhs, now: Date())
            let right = sortKey(for: rhs, now: Date())
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            if left.time != right.time {
                return left.time < right.time
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Prioritize an upcoming, actionable session instead of the first row
    /// in a calendar, which may already have been completed or skipped.
    private func sortKey(
        for entry: TodayEntry,
        now: Date
    ) -> (priority: Int, time: Date) {
        if isSkipped(entry) || isCompleted(entry) || isPartlyCompleted(entry) {
            return (3, effectiveStart(entry.session))
        }
        let time = effectiveStart(entry.session)
        if time >= now { return (0, time) }
        return (1, time)
    }

    private func effectiveStart(_ workout: PlannedSession) -> Date {
        let calendar = Calendar.current
        if workout.scheduledTimeIsExplicit != false,
           let scheduled = workout.scheduledStart {
            let clock = calendar.dateComponents([.hour, .minute], from: scheduled)
            if clock.hour != 0 || clock.minute != 0 {
                return scheduled
            }
        }
        // Date-only sessions use the established default planning hour.
        return calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func isSkipped(_ entry: TodayEntry) -> Bool {
        guard !entry.standalone, let planID = session.activePlan?.id else {
            return false
        }
        return session.isPlanSessionSkipped(
            planID: planID, sessionID: entry.id
        )
    }

    private func isCompleted(_ entry: TodayEntry) -> Bool {
        if !entry.standalone, let planID = session.activePlan?.id,
           session.isPlanSessionManuallyCompleted(
                planID: planID, sessionID: entry.id
           ) {
            return true
        }
        return strength.workoutHistory.contains {
            $0.plannedSessionID == entry.id && $0.isFullyCompleted
        }
    }

    private func isPartlyCompleted(_ entry: TodayEntry) -> Bool {
        !isCompleted(entry) && strength.workoutHistory.contains {
            $0.plannedSessionID == entry.id && $0.isFinished
        }
    }

    private var actionableToday: [TodayEntry] {
        allToday.filter {
            !isSkipped($0) && !isCompleted($0) && !isPartlyCompleted($0)
        }
    }

    private var otherToday: [TodayEntry] {
        let featuredID = actionableToday.first?.id
        return allToday.filter { $0.id != featuredID }
    }

    private func recordedStatus(
        _ workout: PlannedSession,
        standalone: Bool
    ) -> String? {
        let entry = TodayEntry(session: workout, standalone: standalone)
        if isSkipped(entry) {
            return ATHLTHLocalization.choose(
                english: "Skipped", norwegian: "Hoppet over"
            )
        }
        if isCompleted(entry) {
            return ATHLTHLocalization.choose(
                english: "Completed", norwegian: "Gjennomført"
            )
        }
        if isPartlyCompleted(entry) {
            return ATHLTHLocalization.choose(
                english: "Partly completed", norwegian: "Delvis gjennomført"
            )
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            introduction

            if let featured = actionableToday.first {
                featuredWorkout(featured.session, standalone: featured.standalone)
            } else if allToday.isEmpty {
                if isPlannedRestDayToday {
                    restDayCard
                } else {
                    unscheduledDay
                }
            } else {
                dayCompleted
            }

            if !otherToday.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel(ATHLTHLocalization.choose(
                        english: "OTHER SESSIONS", norwegian: "ANDRE ØKTER"
                    ))
                    ForEach(otherToday) { item in
                        compactWorkout(item.session, standalone: item.standalone)
                    }
                }
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
                if let status = recordedStatus(
                    workout, standalone: standalone
                ) {
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
                if let status = recordedStatus(
                    workout, standalone: standalone
                ) {
                    Text(status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .lineLimit(1)
                }
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

    private var dayCompleted: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ATHLTHLocalization.choose(
                english: "Nothing else planned today",
                norwegian: "Ingen flere økter står for tur i dag"
            ))
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.primaryText)
            Text(ATHLTHLocalization.choose(
                english: "Your completed and skipped sessions are listed below.",
                norwegian: "Gjennomførte og hoppede økter finner du nedenfor."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.white, in: RoundedRectangle(cornerRadius: 21)
        )
    }

    private var restDayCard: some View {
        Button(action: onOpenPlan) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: "leaf")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "Rest day",
                        norwegian: "Hviledag"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(ATHLTHLocalization.choose(
                        english: "Intentionally planned rest. It does not count as a missed workout.",
                        norwegian: "Planlagt hvile. Dagen teller ikke som en økt du har hoppet over."
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
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Open your plan to edit the rest day.",
            norwegian: "Åpner treningsplanen hvor du kan endre hviledagen."
        ))
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
                        english: "Choose a workout to plan or start freely.",
                        norwegian: "Planlegg en økt, eller tren fritt."
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
