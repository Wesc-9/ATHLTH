import SwiftUI

/// Shared first step for personal planning. The recovery entry opens the
/// same recovery/rest-day planner used by the Library and Plan Studio.
struct WorkoutPlanningSourceCard: View {
    let context: String
    let onCreateNew: () -> Void
    let onUsePlanned: () -> Void
    let onRecoveryRest: (() -> Void)?

    init(
        context: String,
        onCreateNew: @escaping () -> Void,
        onUsePlanned: @escaping () -> Void,
        onRecoveryRest: (() -> Void)? = nil
    ) {
        self.context = context
        self.onCreateNew = onCreateNew
        self.onUsePlanned = onUsePlanned
        self.onRecoveryRest = onRecoveryRest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ATHLTH · PLAN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.2)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                Text(ATHLTHLocalization.choose(
                    english: "How do you want to start?",
                    norwegian: "Hvordan vil du starte?"
                ))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 1)

            HStack(alignment: .top, spacing: 12) {
                sourceTile(
                    title: ATHLTHLocalization.choose(
                        english: "Start from scratch",
                        norwegian: "Fra bunnen av"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Build a new workout with all the planning options.",
                        norwegian: "Bygg en ny økt med alle planleggingsvalgene."
                    ),
                    icon: "plus.circle.fill",
                    imageName: "GoalRunning",
                    tint: ATHLTHTheme.vitality,
                    action: onCreateNew
                )

                sourceTile(
                    title: ATHLTHLocalization.choose(
                        english: "Use a planned workout",
                        norwegian: "Bruk planlagt økt"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Choose and adjust a workout you've already planned.",
                        norwegian: "Hent og tilpass en økt du allerede har planlagt."
                    ),
                    icon: "calendar",
                    imageName: "GoalStrength",
                    tint: ATHLTHTheme.accentDeep,
                    action: onUsePlanned
                )
            }

            if let onRecoveryRest {
                Button(action: onRecoveryRest) {
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 45, height: 45)
                            .background(
                                ATHLTHTheme.recoveryBlueSoft,
                                in: RoundedRectangle(cornerRadius: 14)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "Recovery / rest day",
                                norwegian: "Restitusjon / hviledag"
                            ))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                            Text(ATHLTHLocalization.choose(
                                english: "Plan gentle recovery or a full day off.",
                                norwegian: "Planlegg lett restitusjon eller en hel hviledag."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 3)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.white.opacity(0.86),
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ATHLTHTheme.border.opacity(0.65), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Plan recovery or a rest day",
                    norwegian: "Planlegg restitusjon eller hviledag"
                ))
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 21)

                Text(ATHLTHLocalization.choose(
                    english: "Tip: You can change the type, time, exercises and other details in the next step.",
                    norwegian: "Tips: Du kan endre type, tid, øvelser og andre detaljer i neste steg."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTheme.surfaceStone.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .padding(.horizontal, 2)
    }

    /// Full-bleed portrait photo cards matching the selected start design.
    /// The bright upper gradient keeps titles legible over any goal artwork,
    /// while the lower image stays visible all the way to the rounded edges.
    private func sourceTile(
        title: String,
        subtitle: String,
        icon: String,
        imageName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.94), location: 0),
                            .init(color: Color.white.opacity(0.91), location: 0.25),
                            .init(color: Color.white.opacity(0.78), location: 0.44),
                            .init(color: Color.white.opacity(0.26), location: 0.66),
                            .init(color: Color.clear, location: 0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: [
                            tint.opacity(0.07),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 43, height: 43)
                            .background(Color.white.opacity(0.94), in: Circle())

                        Text(title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 17)

                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.78))
                            .lineLimit(4)
                            .minimumScaleFactor(0.86)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 6)

                        Spacer(minLength: 12)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 43, height: 43)
                            .background(
                                Color.white.opacity(0.97),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                            }
                    }
                    .padding(15)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .topLeading
                    )
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                }
            }
            .frame(height: 315)
            .contentShape(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .frame(maxWidth: .infinity)
    }
}


/// Shared planner for an easy recovery session or a genuine rest day.
/// Works without Apple Watch and does not create a completed workout.
struct ATHLTHRecoveryRestPlanningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    enum Mode: String, CaseIterable, Identifiable {
        case recovery, rest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recovery: return ATHLTHLocalization.choose(
                english: "Active recovery", norwegian: "Aktiv restitusjon")
            case .rest: return ATHLTHLocalization.choose(
                english: "Rest day", norwegian: "Hviledag")
            }
        }
        var explanation: String {
            switch self {
            case .recovery: return ATHLTHLocalization.choose(
                english: "Light movement, mobility or recovery without a hard training target.",
                norwegian: "Rolig bevegelse, mobilitet eller restitusjon uten harde treningsmål.")
            case .rest: return ATHLTHLocalization.choose(
                english: "A planned day off. No workout, watch, training load or completion required.",
                norwegian: "En planlagt treningsfri dag. Ingen økt, klokke, belastning eller fullføring kreves.")
            }
        }
        var symbol: String { self == .rest ? "moon.stars.fill" : "leaf.fill" }
    }

    private struct PlanDay: Identifiable {
        let planID: UUID
        let dayID: UUID
        let title: String
        let date: Date?
        let hasWorkouts: Bool
        var id: UUID { dayID }
    }

    private let fixedPlanID: UUID?
    private let fixedDayID: UUID?
    @State private var selectedPlanID: UUID?
    @State private var selectedDayID: UUID?
    @State private var date: Date
    @State private var mode: Mode = .recovery
    @State private var durationMinutes = 20
    @State private var notes = ""
    @State private var errorMessage: String?

    init(date: Date = Date(), planID: UUID? = nil, dayID: UUID? = nil) {
        fixedPlanID = planID
        fixedDayID = dayID
        _selectedPlanID = State(initialValue: planID)
        _selectedDayID = State(initialValue: dayID)
        _date = State(initialValue: date)
    }

    private var selectedPlan: TrainingPlan? {
        guard let selectedPlanID else { return nil }
        return session.trainingPlan(withID: selectedPlanID)
    }

    private var availableDays: [PlanDay] {
        guard let plan = selectedPlan else { return [] }
        let calendar = Calendar.current
        return plan.weeks.enumerated().flatMap { weekIndex, week in
            week.days.sorted(by: { $0.dayIndex < $1.dayIndex }).map { day in
                let dayDate = plan.startDate.flatMap {
                    calendar.date(
                        byAdding: .day,
                        value: weekIndex * 7 + day.dayIndex - 1,
                        to: calendar.startOfDay(for: $0)
                    )
                }
                let label = ATHLTHLocalization.format(
                    english: "Week %d · Day %d",
                    norwegian: "Uke %d · Dag %d",
                    weekIndex + 1, day.dayIndex
                )
                return PlanDay(
                    planID: plan.id,
                    dayID: day.id,
                    title: dayDate.map {
                        label + " · " + $0.formatted(date: .abbreviated, time: .omitted)
                    } ?? label,
                    date: dayDate,
                    hasWorkouts: day.sessions.contains { !$0.isExplicitRestDay }
                )
            }
        }
    }

    private var selectedDay: PlanDay? {
        availableDays.first { $0.dayID == selectedDayID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("ATHLTH · RECOVERY")
                            .font(.caption2.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(ATHLTHLocalization.choose(
                            english: "Plan recovery",
                            norwegian: "Planlegg restitusjon"
                        ))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text(ATHLTHLocalization.choose(
                            english: "Recovery is part of training. Choose what this day needs.",
                            norwegian: "Restitusjon er en del av treningen. Velg hva dagen skal brukes til."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        ForEach(Mode.allCases) { choice in
                            Button {
                                mode = choice
                                errorMessage = nil
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: choice.symbol)
                                        .font(.title3)
                                        .foregroundStyle(ATHLTHTheme.recoveryBlue)
                                        .frame(width: 42, height: 42)
                                        .background(
                                            ATHLTHTheme.recoveryBlueSoft,
                                            in: RoundedRectangle(cornerRadius: 13)
                                        )
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(choice.title)
                                            .font(.headline)
                                            .foregroundStyle(ATHLTHTheme.primaryText)
                                        Text(choice.explanation)
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 5)
                                    Image(systemName: mode == choice ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                                .padding(15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    mode == choice ? ATHLTHTheme.recoveryBlueSoft.opacity(0.55) : .white,
                                    in: RoundedRectangle(cornerRadius: 18)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(
                                            mode == choice ? ATHLTHTheme.recoveryBlue : ATHLTHTheme.border,
                                            lineWidth: mode == choice ? 1.4 : 0.8
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        Text(ATHLTHLocalization.choose(
                            english: "Schedule", norwegian: "Planlegg"
                        ))
                        .font(.headline)

                        if fixedPlanID == nil {
                            Picker(
                                ATHLTHLocalization.choose(
                                    english: "Add to", norwegian: "Legg til i"
                                ),
                                selection: $selectedPlanID
                            ) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Extra calendar entry",
                                    norwegian: "Ekstra i kalenderen"
                                ))
                                .tag(nil as UUID?)

                                ForEach(session.trainingPlans) { plan in
                                    Text(plan.title).tag(plan.id as UUID?)
                                }
                            }
                            .onChange(of: selectedPlanID) { _, _ in
                                selectedDayID = nil
                                errorMessage = nil
                            }
                        }

                        if selectedPlanID != nil {
                            if fixedDayID == nil {
                                Picker(
                                    ATHLTHLocalization.choose(
                                        english: "Choose plan day",
                                        norwegian: "Velg dag i treningsplanen"
                                    ),
                                    selection: $selectedDayID
                                ) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Select day", norwegian: "Velg dag"
                                    ))
                                    .tag(nil as UUID?)
                                    ForEach(availableDays) { day in
                                        Text(day.title).tag(day.dayID as UUID?)
                                    }
                                }
                            } else if let selectedDay {
                                Label(selectedDay.title, systemImage: "calendar")
                                    .font(.subheadline)
                            }

                            if mode == .rest && selectedDay?.hasWorkouts == true {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "This day already has training. Remove those sessions before marking the day as rest.",
                                        norwegian: "Dagen har allerede trening. Fjern øktene før du markerer den som hviledag."
                                    ),
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            }
                        } else {
                            DatePicker(
                                ATHLTHLocalization.choose(
                                    english: "Date", norwegian: "Dato"
                                ),
                                selection: $date,
                                in: Calendar.current.startOfDay(for: Date())...,
                                displayedComponents: .date
                            )
                        }

                        if mode == .recovery {
                            Stepper(
                                ATHLTHLocalization.format(
                                    english: "%d minutes of easy recovery",
                                    norwegian: "%d minutter rolig restitusjon",
                                    durationMinutes
                                ),
                                value: $durationMinutes,
                                in: 5...180,
                                step: 5
                            )
                        }

                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Optional notes", norwegian: "Notater (valgfritt)"
                            ),
                            text: $notes,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Recovery / Rest", norwegian: "Restitusjon / hvile"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) { save() }
                    .fontWeight(.semibold)
                    .disabled(selectedPlanID != nil && selectedDay == nil)
                }
            }
        }
    }

    private func save() {
        let destinationDay = selectedDay
        if selectedPlanID != nil && destinationDay == nil {
            errorMessage = ATHLTHLocalization.choose(
                english: "Select a day in the training plan.",
                norwegian: "Velg en dag i treningsplanen."
            )
            return
        }
        guard mode != .rest || destinationDay?.hasWorkouts != true else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Remove the existing workouts first.",
                norwegian: "Fjern de eksisterende øktene først."
            )
            return
        }
        if let destinationDay, let plan = selectedPlan {
            let existing = plan.weeks.flatMap(\.days)
                .first(where: { $0.id == destinationDay.dayID })?.sessions ?? []
            guard !existing.contains(where: { $0.isExplicitRestDay }) else {
                errorMessage = ATHLTHLocalization.choose(
                    english: "This day is already marked as rest. Remove it before adding another entry.",
                    norwegian: "Denne dagen er allerede hviledag. Fjern markeringen før du legger til noe nytt."
                )
                return
            }
        }

        let isRest = mode == .rest
        let sessionDate = destinationDay?.date ?? date
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let planned = PlannedSession(
            id: UUID(),
            title: mode.title,
            kind: .recovery,
            scheduledStart: selectedPlanID == nil
                ? Calendar.current.startOfDay(for: sessionDate) : destinationDay?.date,
            durationMinutes: isRest ? nil : durationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            workoutCategory: isRest ? "rest_day" : "recovery"
        )

        if let selectedPlanID, let destinationDay {
            session.addSession(planned, toDay: destinationDay.dayID, inPlan: selectedPlanID)
        } else {
            session.addStandalonePlannedSession(planned)
        }
        dismiss()
    }
}
