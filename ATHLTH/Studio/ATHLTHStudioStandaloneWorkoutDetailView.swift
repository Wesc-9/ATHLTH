import SwiftUI

/// Direct detail and safe metadata editing for independently scheduled
/// workouts. This never converts a standalone workout into a plan workout
/// and never starts a new activity merely by opening its details.
struct ATHLTHStudioStandaloneWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let workoutID: UUID

    @State private var editing = false
    @State private var original: PlannedSession?
    @State private var title = ""
    @State private var scheduledDate = Date.now
    @State private var minutes = 45
    @State private var hasDuration = true
    @State private var notes = ""
    @State private var warning: String?

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var workout: PlannedSession? {
        session.standalonePlannedSessions.first { $0.id == workoutID }
    }

    private var isFutureOrToday: Bool {
        guard let date = workout?.scheduledStart else { return false }
        return Calendar.current.startOfDay(for: date) >=
            Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let workout {
                    VStack(alignment: .leading, spacing: 18) {
                        heading(workout)
                        if editing {
                            editForm
                        } else {
                            overview(workout)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 630)
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView(
                        tr("Workout no longer available", "Økten finnes ikke lenger"),
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(tr(
                            "The independent planned workout was removed or updated.",
                            "Den frittstående økten er fjernet eller endret."
                        ))
                    )
                }
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
            .navigationTitle(tr("Workout details", "Øktdetaljer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if workout != nil, isFutureOrToday {
                        if editing {
                            Button(tr("Save", "Lagre")) { save() }
                                .fontWeight(.semibold)
                        } else {
                            Button(tr("Edit", "Rediger")) { beginEdit() }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 620, maxWidth: 720)
        .frame(minHeight: 460, idealHeight: 675)
        .alert(
            tr("Workout not saved", "Økten ble ikke lagret"),
            isPresented: Binding(
                get: { warning != nil },
                set: { if !$0 { warning = nil } }
            )
        ) {
            Button("OK", role: .cancel) { warning = nil }
        } message: {
            Text(warning ?? "")
        }
    }

    private func heading(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    tr("INDEPENDENT WORKOUT", "FRITTSTÅENDE ØKT"),
                    systemImage: workout.kind.systemImage
                )
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Spacer()
            }
            Text(workout.title)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(ATHLTHStudioStyle.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let start = workout.scheduledStart {
                Label(
                    start.formatted(date: .complete, time: .shortened),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Text(tr(
                "Scheduled separately from training programs",
                "Planlagt utenfor treningsprogrammene"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func overview(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                summaryMetric(
                    title: tr("Activity", "Aktivitet"),
                    value: workout.kind.title,
                    symbol: workout.kind.systemImage
                )
                summaryMetric(
                    title: tr("Duration", "Varighet"),
                    value: workout.durationMinutes.map { "\($0) min" } ?? "—",
                    symbol: "clock"
                )
                if let distance = workout.targetDistanceKilometers {
                    summaryMetric(
                        title: tr("Distance", "Distanse"),
                        value: String(format: "%.1f km", distance),
                        symbol: "point.bottomleft.forward.to.point.topright.scurvepath"
                    )
                }
            }

            if !workout.resolvedWorkoutBlocks.isEmpty || !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Text(tr("Workout structure", "Øktens oppbygning"))
                        .font(.headline)
                        .foregroundStyle(ATHLTHStudioStyle.ink)

                    if let summary = ATHLTHWorkoutContentSummary.text(for: workout) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(
                        Array(workout.resolvedWorkoutBlocks.enumerated()),
                        id: \.offset
                    ) { _, block in
                        Label(block.title, systemImage: "circle.dotted")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                    }
                    ForEach(workout.exercises) { exercise in
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell")
                                .foregroundStyle(ATHLTHStudioStyle.gold)
                            Text(exercise.embeddedExercise.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(exercise.sets) " + tr("sets", "sett"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(19)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }

            if let notes = workout.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Notes", "Notater"))
                        .font(.headline)
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(19)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }

            Text(tr(
                "Opening workout details does not start a workout or mark it completed.",
                "Åpning av øktdetaljer starter ikke økten og markerer den ikke som fullført."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func summaryMetric(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(ATHLTHStudioStyle.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(tr("Edit planned details", "Rediger planlagte detaljer"))
                .font(.headline)
                .foregroundStyle(ATHLTHStudioStyle.ink)

            TextField(tr("Workout name", "Navn på økten"), text: $title)
                .textFieldStyle(.roundedBorder)

            DatePicker(
                tr("Scheduled date and time", "Planlagt dato og tidspunkt"),
                selection: $scheduledDate,
                displayedComponents: [.date, .hourAndMinute]
            )

            Toggle(tr("Planned duration", "Planlagt varighet"), isOn: $hasDuration)
            if hasDuration {
                Stepper(value: $minutes, in: 5...360, step: 5) {
                    Text("\(minutes) min")
                }
            }

            Text(tr("Notes", "Notater"))
                .font(.subheadline.weight(.medium))
            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(8)
                .background(
                    ATHLTHStudioStyle.canvas,
                    in: RoundedRectangle(cornerRadius: 12)
                )

            if let original, !original.resolvedWorkoutBlocks.isEmpty ||
                !original.exercises.isEmpty {
                Label(tr(
                    "Intervals, exercises and sets are preserved exactly as saved.",
                    "Intervaller, øvelser og sett beholdes slik de er lagret."
                ), systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    save()
                } label: {
                    Label(tr("Save", "Lagre"), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)
                .keyboardShortcut("s", modifiers: .command)

                Button(tr("Cancel", "Avbryt")) {
                    editing = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func beginEdit() {
        guard isFutureOrToday, let workout else { return }
        original = workout
        title = workout.title
        scheduledDate = workout.scheduledStart ?? .now
        hasDuration = workout.durationMinutes != nil
        minutes = min(max(workout.durationMinutes ?? 45, 5), 360)
        notes = workout.notes ?? ""
        editing = true
    }

    private func save() {
        guard let previous = original,
              let current = workout,
              current == previous else {
            warning = tr(
                "This workout changed elsewhere. Close and reopen it to avoid overwriting newer edits.",
                "Økten er endret et annet sted. Lukk og åpne den på nytt for å unngå å overskrive nyere endringer."
            )
            return
        }

        let proposed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposed.isEmpty,
              proposed.count <= 120,
              Calendar.current.startOfDay(for: scheduledDate) >=
                Calendar.current.startOfDay(for: .now) else {
            warning = tr(
                "Enter a name (up to 120 characters) and a date that is today or later.",
                "Oppgi et navn på høyst 120 tegn og en dato som er i dag eller senere."
            )
            return
        }

        var update = current
        update.title = proposed
        update.scheduledStart = scheduledDate
        update.durationMinutes = hasDuration ? minutes : nil
        let cleaned = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        update.notes = cleaned.isEmpty ? nil : cleaned
        session.updateStandalonePlannedSession(update)

        original = update
        editing = false
    }
}
