import SwiftUI

/// Independent plan-workout relocation sheet. Owns its transient date and error
/// state so the large Plan workspace does not rebuild on every calendar tap.
struct ATHLTHTrainMoveWorkoutSheet: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let workout: PlannedSession
    let expectedVersion: Int
    let advanced: Bool
    let onSaved: (Date) -> Void
    let onCancel: () -> Void

    @State private var targetDate: Date
    @State private var weekDate: Date
    @State private var error: String?

    init(
        plan: TrainingPlan,
        workout: PlannedSession,
        expectedVersion: Int,
        initialDate: Date,
        advanced: Bool,
        onSaved: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.plan = plan
        self.workout = workout
        self.expectedVersion = expectedVersion
        self.advanced = advanced
        self.onSaved = onSaved
        self.onCancel = onCancel
        _targetDate = State(initialValue: initialDate)
        _weekDate = State(initialValue: initialDate)
    }

    private var bounds: ClosedRange<Date>? {
        ATHLTHTrainWorkoutMovePolicy.allowedDates(
            startDate: plan.startDate, weekCount: plan.weeks.count
        )
    }

    private var originalDate: Date? {
        ATHLTHTrainWorkoutMovePolicy.originalDate(
            for: workout.id, in: plan
        )
    }

    private var canSave: Bool {
        ATHLTHTrainWorkoutMovePolicy.canMove(
            to: targetDate, from: originalDate, within: bounds
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let bounds {
                        if advanced {
                            DatePicker(
                                tr("New workout date", "Ny treningsdato"),
                                selection: $targetDate,
                                in: bounds,
                                displayedComponents: .date
                            )
                        } else {
                            simpleMoveDays(earliest: bounds.lowerBound, last: bounds.upperBound)
                        }
                    } else if plan.startDate == nil || plan.weeks.isEmpty {
                        Text(tr("The plan has no valid date range.",
                                "Planen mangler en gyldig datoperiode."))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(tr("This plan has no upcoming dates.",
                                "Denne planen har ingen kommende datoer."))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(tr(
                        "Choose a date within the plan. Completed and skipped workouts cannot be moved.",
                        "Velg en dato innenfor planen. Gjennomførte og hoppede økter kan ikke flyttes."
                    ))
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(tr("Move workout", "Flytt økt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Lagre"), action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            // A past source date must not become the initial selection in
            // a DatePicker restricted to today and future planned days.
            if let bounds, !bounds.contains(Calendar.current.startOfDay(for: targetDate)) {
                targetDate = bounds.lowerBound
                weekDate = targetDate
            }
        }
    }

    private func save() {
        guard canSave else { return }
        if session.movePlanStudioWorkout(
            planID: plan.id,
            workoutID: workout.id,
            targetDate: targetDate,
            expectedVersion: expectedVersion,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        ) {
            onSaved(targetDate)
        } else {
            error = tr(
                "Could not move this workout. Check the date or refresh the plan.",
                "Kunne ikke flytte økten. Kontroller datoen eller oppdater planen."
            )
        }
    }

    private func simpleMoveDays(earliest: Date, last: Date) -> some View {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekDate)?.start ?? weekDate
        let dates = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("Choose a new day", "Velg en ny dag"))
                .font(.headline)
            HStack {
                Button {
                    weekDate = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.left").frame(width: 48, height: 48)
                }
                .disabled(weekStart <= earliest)
                .accessibilityLabel(tr("Previous week", "Forrige uke"))
                Spacer()
                Text(weekStart.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    weekDate = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.right").frame(width: 48, height: 48)
                }
                .disabled((dates.last ?? weekStart) >= last)
                .accessibilityLabel(tr("Next week", "Neste uke"))
            }
            ForEach(dates, id: \.self) { date in
                let selected = calendar.isDate(date, inSameDayAs: targetDate)
                Button {
                    targetDate = date
                    error = nil
                } label: {
                    HStack {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill") }
                    }
                    .foregroundStyle(selected ? Color.white : ATHLTHTrainDesign.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(
                        selected ? ATHLTHTrainDesign.ink : ATHLTHTrainDesign.paleGold,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .disabled(date < earliest || date > last)
                .opacity(date < earliest || date > last ? 0.35 : 1)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}
