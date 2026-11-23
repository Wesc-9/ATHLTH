import SwiftUI

/// Decision shared by the seven-day rail and the previous/next-week buttons.
/// Entry-screen preferences are not a workout draft; entering the workout
/// builder marks the point at which a date-scoped draft needs protecting.
enum ATHLTHStudioDayChangePolicy {
    enum Decision: Equatable {
        case unchanged
        case switchImmediately
        case confirmDraft
    }

    static func decision(
        current: Date,
        proposed: Date,
        hasStartedWorkout: Bool,
        calendar: Calendar = .current
    ) -> Decision {
        guard !calendar.isDate(current, inSameDayAs: proposed) else {
            return .unchanged
        }
        return hasStartedWorkout ? .confirmDraft : .switchImmediately
    }
}

/// Vertical cards are always measured against the height of their actual
/// container, never hard-coded to seven rows taller than the iPad window.
enum ATHLTHStudioWeekRailLayout {
    static let headerHeight: CGFloat = 54
    static let horizontalInset: CGFloat = 9
    static let verticalInset: CGFloat = 9
    static let sectionSpacing: CGFloat = 9
    static let daySpacing: CGFloat = 7

    static func useVerticalRail(width: CGFloat, height: CGFloat) -> Bool {
        width >= 680 && height >= 600
    }

    static func width(in availableWidth: CGFloat) -> CGFloat {
        min(256, max(166, availableWidth * 0.19))
    }

    static func dayHeight(for availableHeight: CGFloat) -> CGFloat {
        let remaining = availableHeight -
            2 * verticalInset - headerHeight - sectionSpacing - 6 * daySpacing
        return min(99, max(44, remaining / 7))
    }

    static func weekNumber(for date: Date, timeZone: TimeZone = .current) -> Int {
        // Always agree with Monday-first weekRange, including around New Year
        // for athletes whose device region is not set to Norway.
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar.component(.weekOfYear, from: date)
    }
}

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
    // Chosen before entering the same Basic/Advanced editor used on iPhone.
    // The editor still allows switching modes without losing the recipe.
    @State private var preferredAdvanced = false

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
        HomeWeeklyProgressCalendar.canScheduleStandalone(on: selectedDate)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar

                if ATHLTHStudioWeekRailLayout.useVerticalRail(
                    width: geometry.size.width, height: geometry.size.height
                ) {
                    HStack(spacing: 0) {
                        dayRail
                            .frame(width: ATHLTHStudioWeekRailLayout.width(
                                in: geometry.size.width
                            ))
                        Rectangle()
                            .fill(ATHLTHStudioStyle.outline.opacity(0.7))
                            .frame(width: 1)
                        editorArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        // In a short or narrow Stage Manager window, all
                        // seven days wrap into one or two rows. No horizontal
                        // swipe or clipped Sunday card is required.
                        compactDayStrip(width: geometry.size.width)
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

            // Week controls live immediately above Monday in the rail,
            // not over the selected-day text or the Inbox edge handle.
            Spacer(minLength: 5)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 66)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            ATHLTHStudioStyle.outline.opacity(0.5).frame(height: 1)
        }
    }

    private var weekNavigationHeader: some View {
        HStack(spacing: 3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ATHLTHLocalization.choose(
                    english: "Week \(ATHLTHStudioWeekRailLayout.weekNumber(for: selectedDate))",
                    norwegian: "Uke \(ATHLTHStudioWeekRailLayout.weekNumber(for: selectedDate))"
                ))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHStudioStyle.ink)
                Text(weekDateRangeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHStudioStyle.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 1)
            Button { changeWeek(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Previous week", norwegian: "Forrige uke"
            ))
            Button { changeWeek(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Next week", norwegian: "Neste uke"
            ))
        }
        .buttonStyle(.plain)
        .foregroundStyle(ATHLTHStudioStyle.gold)
        .frame(height: ATHLTHStudioWeekRailLayout.headerHeight)
        .accessibilityIdentifier("athlth-ipad-week-rail-navigation")
    }

    private var weekDateRangeLabel: String {
        let range = ATHLTHStudioHomeWeek.weekRange(containing: selectedDate)
        return range.start.formatted(.dateTime.day()) + "–" +
            range.end.formatted(.dateTime.day().month(.abbreviated))
    }

    private var dayRail: some View {
        GeometryReader { proxy in
            let tileHeight = ATHLTHStudioWeekRailLayout.dayHeight(
                for: proxy.size.height
            )
            VStack(spacing: ATHLTHStudioWeekRailLayout.sectionSpacing) {
                weekNavigationHeader
                VStack(spacing: ATHLTHStudioWeekRailLayout.daySpacing) {
                    ForEach(snapshot.days) { day in
                        dayButton(day, compact: false, verticalHeight: tileHeight)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ATHLTHStudioWeekRailLayout.horizontalInset)
            .padding(.vertical, ATHLTHStudioWeekRailLayout.verticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(ATHLTHStudioStyle.canvas)
        .accessibilityIdentifier("athlth-ipad-vertical-day-rail")
    }

    private func compactDayStrip(width: CGFloat) -> some View {
        let columnCount = width >= 620 ? 7 : 4
        return VStack(spacing: 5) {
            weekNavigationHeader
                .padding(.horizontal, 12)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 0), spacing: 6),
                    count: columnCount
                ),
                spacing: 6
            ) {
                ForEach(snapshot.days) { day in
                    dayButton(day, compact: true)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 8)
        }
        .background(ATHLTHStudioStyle.canvas)
        .accessibilityIdentifier("athlth-ipad-compact-week-rail")
    }

    private func dayButton(
        _ day: ATHLTHStudioHomeWeek.Day,
        compact: Bool,
        verticalHeight: CGFloat? = nil
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
                requestDayChange(to: day.date)
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
            .padding(.horizontal, compact ? 6 : 12)
            .padding(.vertical, compact ? 9 : 8)
            .frame(
                maxWidth: .infinity,
                minHeight: compact ? 66 : (verticalHeight ?? 78),
                alignment: .leading
            )
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
                        initialStudioAdvanced: preferredAdvanced,
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

    /// The iPad-specific choice surface shares the iPhone activity catalog
    /// and opens the existing WorkoutTemplateBuilderView. No second engine
    /// or duplicate draft persistence is introduced by this presentation.
    private var activitySelection: some View {
        ATHLTHStudioWorkoutEntryView(
            date: selectedDate,
            plannedWorkouts: snapshot.days.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
            })?.planned.map(\.workout) ?? [],
            scheduledTime: $scheduledTime,
            advanced: $preferredAdvanced,
            onChoose: { type in
                selectedActivity = type
            }
        )
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
        requestDayChange(to: proposed)
    }

    /// Do not warn about an unsaved workout before one has been started.
    /// Date/time and Basic/Advanced preferences on the entry screen are
    /// not an authored workout. Both the day rail and week arrows use this
    /// single path so neither can raise a false draft confirmation.
    private func requestDayChange(to proposed: Date) {
        let nextDate = Calendar.current.startOfDay(for: proposed)
        switch ATHLTHStudioDayChangePolicy.decision(
            current: selectedDate,
            proposed: nextDate,
            hasStartedWorkout: selectedActivity != nil
        ) {
        case .unchanged:
            return
        case .switchImmediately:
            switchToDay(nextDate)
        case .confirmDraft:
            // The user entered the shared workout builder. Keep its local,
            // date-scoped draft and ask before replacing that editor.
            pendingDate = nextDate
        }
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
