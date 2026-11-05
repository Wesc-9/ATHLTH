import SwiftUI

/// Focused iPad day planning: week navigation and one reusable iPhone
/// workout builder on the same screen. No modal, parallel workout engine,
/// or implicit completion of saved Health workouts.
struct ATHLTHStudioFocusedWeekPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let onClose: () -> Void
    @State private var selectedDate: Date
    @State private var scheduledTime: Date
    @State private var pendingDate: Date?
    @State private var saveMessage: String?
    @State private var saveSucceeded = false
    @State private var selectedActivity: ATHLTHPlannedWorkoutType?

    init(initialDate: Date, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let start = Calendar.current.startOfDay(for: initialDate)
        _selectedDate = State(initialValue: start)
        _scheduledTime = State(initialValue:
            Calendar.current.date(
                bySettingHour: 18, minute: 0, second: 0, of: start
            ) ?? start)
    }

    private var snapshot: ATHLTHStudioHomeWeek.Snapshot {
        ATHLTHStudioHomeWeek.make(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            recorded: health.healthDataAvailable && health.hasRequestedAuthorization
                ? health.workouts : [],
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: selectedDate
        )
    }

    private var editable: Bool {
        Calendar.current.startOfDay(for: selectedDate) >=
            Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar

                if geometry.size.width >= 680 {
                    HStack(spacing: 0) {
                        dayRail
                            .frame(width: min(222, max(144, geometry.size.width * 0.17)))
                        Rectangle()
                            .fill(ATHLTHStudioStyle.outline.opacity(0.7))
                            .frame(width: 1)
                        editorArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Stage Manager can resize an iPad window to phone
                        // width. The week remains available without squeezing
                        // the workout editor into an unusably narrow pane.
                        compactDayStrip
                        editorArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Change day and keep this draft?",
                norwegian: "Bytt dag og behold øktutkastet?"
            ),
            isPresented: Binding(
                get: { pendingDate != nil },
                set: { if !$0 { pendingDate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Save draft and change day",
                norwegian: "Behold utkast og bytt dag"
            )) {
                if let pendingDate { switchToDay(pendingDate) }
            }
            Button(ATHLTHLocalization.choose(
                english: "Continue editing", norwegian: "Fortsett å redigere"
            ), role: .cancel) {
                pendingDate = nil
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Your workout draft is stored locally for this date. Switching dates does not save it as a scheduled workout.",
                norwegian: "Øktutkastet lagres lokalt for denne datoen. Å bytte dato betyr ikke at økten er ferdig planlagt."
            ))
        }
    }

    private var topBar: some View {
        HStack(spacing: 13) {
            Button(action: onClose) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Back to overview", norwegian: "Tilbake til oversikt"
                    ),
                    systemImage: "chevron.left"
                )
            }
            .buttonStyle(.borderless)

            Rectangle()
                .fill(ATHLTHStudioStyle.outline)
                .frame(width: 1, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(ATHLTHLocalization.choose(
                    english: "PLAN A WORKOUT", norwegian: "PLANLEGG ØKT"
                ))
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Text(selectedDate.formatted(
                    .dateTime.weekday(.wide).day().month(.wide)
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHStudioStyle.ink)
            }

            Spacer(minLength: 5)
            HStack(spacing: 5) {
                Button {
                    changeWeek(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Previous week", norwegian: "Forrige uke"
                ))

                Text(ATHLTHStudioHomeWeek.weekRange(
                    containing: selectedDate
                ).start.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Button {
                    changeWeek(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Next week", norwegian: "Neste uke"
                ))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 66)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            ATHLTHStudioStyle.outline.opacity(0.5).frame(height: 1)
        }
    }

    private var dayRail: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(snapshot.days) { day in
                    dayButton(day, compact: false)
                }
            }
            .padding(10)
        }
        .background(ATHLTHStudioStyle.canvas)
        .accessibilityIdentifier("athlth-ipad-vertical-day-rail")
    }

    private var compactDayStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(snapshot.days) { day in
                    dayButton(day, compact: true)
                        .frame(width: 114)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
    }

    private func dayButton(
        _ day: ATHLTHStudioHomeWeek.Day,
        compact: Bool
    ) -> some View {
        let selected = Calendar.current.isDate(
            selectedDate, inSameDayAs: day.date
        )
        let completedPlanned = day.planned.filter { entry in
            guard let planID = entry.planID else { return false }
            return session.isPlanSessionCompleted(
                planID: planID, sessionID: entry.workout.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }.count

        return Button {
            if !selected {
                pendingDate = day.date
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(day.date.formatted(.dateTime.day()))
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(ATHLTHStudioStyle.ink)

                HStack(spacing: 5) {
                    if !day.planned.isEmpty {
                        Image(systemName: "calendar")
                        Text("\(day.planned.count)")
                    }
                    if !day.recorded.isEmpty || completedPlanned > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text("\(max(day.recorded.count, completedPlanned))")
                    }
                    if day.planned.isEmpty &&
                       day.recorded.isEmpty && completedPlanned == 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "Free", norwegian: "Ledig"
                        ))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: compact ? 66 : 72,
                   alignment: .leading)
            .background(
                selected ? ATHLTHStudioStyle.paper : Color.white,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? ATHLTHStudioStyle.gold :
                            ATHLTHStudioStyle.outline.opacity(0.45),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var editorArea: some View {
        if !editable {
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "Past days are read-only",
                    norwegian: "Tidligere datoer kan ikke redigeres"
                ),
                systemImage: "calendar.badge.clock",
                description: Text(ATHLTHLocalization.choose(
                    english: "Choose today or a future day to schedule a workout.",
                    norwegian: "Velg i dag eller en fremtidig dato for å planlegge en økt."
                ))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if let saveMessage {
                    Label(saveMessage, systemImage:
                        saveSucceeded ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(saveSucceeded
                            ? ATHLTHStudioStyle.gold : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                }
                if let selectedActivity {
                    WorkoutTemplateBuilderView(
                        draftContext: "ipad-focused-day-\(session.profile.userID.uuidString)-\(dateKey)-\(selectedActivity.rawValue)",
                        plannedDate: scheduledTime,
                        initialActivity: selectedActivity,
                        initialStudioAdvanced: selectedActivity != .running,
                        onScheduledTimeChanged: { scheduledTime = $0 },
                        onAddStandalone: { draft in
                            let saved = saveWorkout(draft, for: selectedDate)
                            if saved { self.selectedActivity = nil }
                            return saved
                        },
                        onValidateSave: { _ in
                            validateDay()
                        },
                        saveButtonTitle: ATHLTHLocalization.choose(
                            english: "Save planned workout",
                            norwegian: "Lagre planlagt økt"
                        ),
                        onCloseInline: { self.selectedActivity = nil }
                    )
                    .environment(\.athlthStudioFullscreenEditing, true)
                    .id("\(dateKey)-\(selectedActivity.rawValue)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    activitySelection
                }
            }
        }
    }

    private var activitySelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Text(ATHLTHLocalization.choose(
                    english: "BUILD A SESSION", norwegian: "BYGG EN ØKT"
                ))
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHStudioStyle.gold)

                Text(ATHLTHLocalization.choose(
                    english: "What are you training?",
                    norwegian: "Hva skal du trene?"
                ))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(ATHLTHStudioStyle.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Choose a discipline, then use Simple or Advanced to build every detail. Your week stays beside the editor.",
                    norwegian: "Velg aktivitet, og bruk Enkel eller Avansert til å bygge økten. Uken blir liggende ved siden av."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 175), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(ATHLTHPlannedWorkoutType.defaultOrder) { type in
                        Button {
                            selectedActivity = type
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.symbol)
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHStudioStyle.gold)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        ATHLTHStudioStyle.canvas,
                                        in: RoundedRectangle(cornerRadius: 11)
                                    )
                                Text(type.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHStudioStyle.ink)
                                Spacer(minLength: 2)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHStudioStyle.gold)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(ATHLTHStudioStyle.outline.opacity(0.7))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(23)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var dateKey: String {
        // Local calendar date, including timezone: no fixed 24h offsets.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day], from: selectedDate
        )
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private struct PlanDay {
        let id: UUID
        let dayID: UUID
        let version: Int
        let hasRestDay: Bool
    }

    private func matchingPlanDay(for date: Date) -> PlanDay? {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: date)
        for plan in session.trainingPlans {
            guard let start = plan.startDate else { continue }
            let delta = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: start), to: target
            ).day ?? -1
            guard delta >= 0,
                  plan.weeks.indices.contains(delta / 7),
                  let day = plan.weeks[delta / 7].days.first(where: {
                      $0.dayIndex == delta % 7 + 1
                  }) else { continue }
            return PlanDay(
                id: plan.id, dayID: day.id, version: plan.version,
                hasRestDay: day.sessions.contains(where: \.isExplicitRestDay)
            )
        }
        return nil
    }

    private func validateDay() -> String? {
        if let match = matchingPlanDay(for: selectedDate),
           match.hasRestDay {
            return ATHLTHLocalization.choose(
                english: "This is a rest day. Remove the rest day in Plan Studio before adding a workout.",
                norwegian: "Dette er en hviledag. Fjern hviledagen i Plan Studio før du legger til en økt."
            )
        }
        return nil
    }

    private func saveWorkout(
        _ proposed: PlannedSession,
        for date: Date
    ) -> Bool {
        guard Calendar.current.startOfDay(for: date) >=
                Calendar.current.startOfDay(for: .now),
              Calendar.current.isDate(date, inSameDayAs: selectedDate)
        else { return false }

        // The shared recipe editor returns a workout without a scheduled date.
        // Use the user's chosen day/time rather than silently saving a
        // template or creating an unintended workout at the current time.
        var workout = proposed
        let calendar = Calendar.current
        let chosenTime = calendar.dateComponents(
            [.hour, .minute, .second], from: scheduledTime
        )
        let when = calendar.date(
            bySettingHour: chosenTime.hour ?? 18,
            minute: chosenTime.minute ?? 0,
            second: chosenTime.second ?? 0,
            of: date
        ) ?? date
        workout.scheduledStart = when

        let saved: Bool
        if let match = matchingPlanDay(for: date) {
            guard !match.hasRestDay else { return false }
            saved = session.savePlanStudioWorkout(
                workout, inPlan: match.id,
                dayID: match.dayID, editingWorkoutID: nil,
                expectedPlanVersion: match.version,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        } else {
            session.addStandalonePlannedSession(workout)
            saved = session.standalonePlannedSessions.contains {
                $0.id == workout.id && $0.scheduledStart == when
            }
        }

        saveSucceeded = saved
        saveMessage = saved
            ? ATHLTHLocalization.choose(
                english: "Workout saved to the chosen date.",
                norwegian: "Økten er lagret på valgt dato."
            )
            : ATHLTHLocalization.choose(
                english: "The day was changed elsewhere. Your draft is safe; review the plan and try again.",
                norwegian: "Dagen ble endret et annet sted. Utkastet er bevart. Kontroller planen og prøv igjen."
            )
        return saved
    }

    private func changeWeek(_ offset: Int) {
        let proposed = ATHLTHStudioHomeWeek.shiftedWeek(
            from: selectedDate, offset: offset
        )
        pendingDate = proposed
    }

    private func switchToDay(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        scheduledTime = Calendar.current.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: selectedDate
        ) ?? selectedDate
        pendingDate = nil
        saveMessage = nil
        saveSucceeded = false
        selectedActivity = nil
    }
}
