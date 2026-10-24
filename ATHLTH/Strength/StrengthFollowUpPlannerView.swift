import SwiftUI

/// Explicit follow-up planning for a *finished* strength recording.
/// This view never edits the original workout or its training plan.
struct StrengthFollowUpPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let workout: StrengthWorkoutLog
    private let remainder: StrengthWorkoutRemainder

    @State private var selectedSetIDs: Set<UUID>
    @State private var onlyRemainderIDs: Set<UUID> = []
    @State private var selectedDay: Date =
        Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
    @State private var hasClockTime = false
    @State private var selectedTime = Calendar.current.date(
        bySettingHour: 18,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var createdSessionID: UUID?

    init(workout: StrengthWorkoutLog) {
        self.workout = workout
        let remaining = StrengthWorkoutRemainder(workout: workout)
        self.remainder = remaining
        _selectedSetIDs = State(initialValue: Set(
            remaining.exercises.flatMap { $0.sets.map(\.sourceSetID) }
        ))
    }

    private var existingFollowUp: PlannedSession? {
        session.standalonePlannedSessions.first {
            $0.followUpSourceWorkoutID == workout.id
        }
    }

    private var scheduledStart: Date {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: selectedDay)
        guard hasClockTime else { return date }
        let hour = calendar.component(.hour, from: selectedTime)
        let minute = calendar.component(.minute, from: selectedTime)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    private var proposedWorkout: PlannedSession? {
        guard workout.isFinished,
              existingFollowUp == nil,
              !selectedSetIDs.isEmpty else { return nil }
        return remainder.makeFollowUp(
            scheduledStart: scheduledStart,
            selectedSetIDs: selectedSetIDs,
            onlyRemainderForSetIDs: onlyRemainderIDs,
            hasExplicitTime: hasClockTime
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let existingFollowUp {
                        existingFollowUpCard(existingFollowUp)
                    } else if !workout.isFinished {
                        Text(ATHLTHLocalization.choose(
                            english: "Finish recording before planning the remaining sets.",
                            norwegian: "Avslutt registreringen før du planlegger gjenstående sett."
                        ))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    } else if remainder.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "There are no unfinished sets to schedule.",
                            norwegian: "Det finnes ingen ufullførte sett å planlegge."
                        ))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        selectionCard
                        dateCard
                        confirmationCard
                    }
                }
                .padding(18)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Plan the rest",
                norwegian: "Planlegg resten"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close",
                        norwegian: "Lukk"
                    )) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: "FOLLOW-UP WORKOUT",
                norwegian: "OPPFØLGINGSØKT"
            ))
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(ATHLTHTheme.premiumGold)

            Text(workout.title)
                .font(.title2.bold())
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Your recorded sets remain unchanged. A follow-up is a new, separate planned session.",
                norwegian: "Registrerte sett beholdes uendret. Oppfølgingen blir en ny, selvstendig planlagt økt."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Unfinished work",
                    norwegian: "Gjenstående innhold"
                ))
                .font(.headline)
                Spacer()
                Text("\(selectedSetIDs.count) / \(remainder.setCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            ForEach(remainder.exercises, id: \.sourceExerciseID) { exercise in
                VStack(alignment: .leading, spacing: 10) {
                    Text(exercise.snapshot.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    ForEach(exercise.sets, id: \.sourceSetID) { set in
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle(isOn: selectedBinding(for: set.sourceSetID)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(wholeTargetLabel(for: set))
                                        .font(.subheadline)
                                    Text(ATHLTHLocalization.choose(
                                        english: "New complete effort suggested",
                                        norwegian: "Nytt fullstendig sett foreslås"
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            }
                            .tint(ATHLTHTheme.premiumGold)

                            if selectedSetIDs.contains(set.sourceSetID),
                               hasPartialProgress(set) {
                                Toggle(
                                    ATHLTHLocalization.choose(
                                        english: "Only remaining amount",
                                        norwegian: "Kun det som gjenstår"
                                    ),
                                    isOn: remainderBinding(for: set.sourceSetID)
                                )
                                .font(.caption)
                                .tint(ATHLTHTheme.premiumGold)

                                if onlyRemainderIDs.contains(set.sourceSetID) {
                                    Text(remainingTargetLabel(for: set))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            ATHLTHTheme.champagneSoft.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(
                english: "When?",
                norwegian: "Når?"
            ))
            .font(.headline)

            DatePicker(
                ATHLTHLocalization.choose(
                    english: "Date",
                    norwegian: "Dato"
                ),
                selection: $selectedDay,
                in: Calendar.current.startOfDay(for: Date())...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)

            Toggle(
                ATHLTHLocalization.choose(
                    english: "Set a start time",
                    norwegian: "Velg klokkeslett"
                ),
                isOn: $hasClockTime
            )
            .tint(ATHLTHTheme.premiumGold)

            if hasClockTime {
                DatePicker(
                    ATHLTHLocalization.choose(
                        english: "Start",
                        norwegian: "Start"
                    ),
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
            }

            let occupied = session.standalonePlannedSessions(
                on: scheduledStart
            )
            if !occupied.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "\(occupied.count) other sessions are scheduled this day. Your existing plan will not be changed.",
                        norwegian: "\(occupied.count) andre økter ligger denne dagen. Eksisterende plan endres ikke."
                    ),
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let proposedWorkout {
                Text(ATHLTHLocalization.choose(
                    english: "\(selectedSetIDs.count) new planned sets",
                    norwegian: "\(selectedSetIDs.count) nye planlagte sett"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

                Text(ATHLTHLocalization.choose(
                    english: "This does not mark the original workout complete or combine separate performances.",
                    norwegian: "Dette fullfører ikke den opprinnelige økten og slår ikke sammen separate prestasjoner."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Button {
                    // Verify the account state and any existing follow-up
                    // immediately before the single confirmed save.
                    guard session.signedIn,
                          existingFollowUp == nil,
                          createdSessionID == nil,
                          let created = session.scheduleStrengthFollowUp(
                              from: workout,
                              on: scheduledStart,
                              selectedSetIDs: selectedSetIDs,
                              onlyRemainderForSetIDs: onlyRemainderIDs,
                              hasExplicitTime: hasClockTime
                          )
                    else { return }
                    createdSessionID = created.id
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Create planned workout",
                            norwegian: "Opprett planlagt økt"
                        ),
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .disabled(createdSessionID != nil)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "Select at least one valid remaining set. Timed strength sets require at least 15 seconds.",
                    norwegian: "Velg minst ett gyldig gjenstående sett. Tidsstyrte styrkesett krever minst 15 sekunder."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
    }

    private func existingFollowUpCard(
        _ followUp: PlannedSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Already planned",
                    norwegian: "Allerede planlagt"
                ),
                systemImage: "calendar.badge.checkmark"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(followUp.title)
                .font(.subheadline)
            if let date = followUp.scheduledStart {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Text(ATHLTHLocalization.choose(
                english: "Only one follow-up can be created from this recording. The planned session can be edited from Plan.",
                norwegian: "Det kan bare opprettes én oppfølgingsøkt fra denne registreringen. Økten kan redigeres fra Plan."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func selectedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedSetIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedSetIDs.insert(id)
                } else {
                    selectedSetIDs.remove(id)
                    onlyRemainderIDs.remove(id)
                }
            }
        )
    }

    private func remainderBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { onlyRemainderIDs.contains(id) },
            set: { enabled in
                if enabled {
                    onlyRemainderIDs.insert(id)
                } else {
                    onlyRemainderIDs.remove(id)
                }
            }
        )
    }

    private func hasPartialProgress(
        _ set: StrengthWorkoutRemainder.Set
    ) -> Bool {
        (set.recordedPartialReps ?? 0) > 0 ||
            (set.recordedPartialDurationSeconds ?? 0) > 0
    }

    private func wholeTargetLabel(
        for set: StrengthWorkoutRemainder.Set
    ) -> String {
        if let seconds = set.plannedDurationSeconds {
            return "\(seconds) sek"
        }
        if let reps = set.plannedReps {
            return "\(reps) reps"
        }
        return ATHLTHLocalization.choose(
            english: "Open target",
            norwegian: "Åpent mål"
        )
    }

    private func remainingTargetLabel(
        for set: StrengthWorkoutRemainder.Set
    ) -> String {
        if let seconds = set.proposedDurationSeconds(
            onlyRemainder: true
        ) {
            return "\(seconds) sek gjenstår"
        }
        if let reps = set.proposedReps(onlyRemainder: true) {
            return "\(reps) repetisjoner gjenstår"
        }
        return ""
    }
}
