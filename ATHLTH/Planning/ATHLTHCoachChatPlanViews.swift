import SwiftUI

private func planText(_ en: String, _ no: String) -> String {
    ATHLTHLocalization.choose(english: en, norwegian: no)
}

/// Compact editorial form for chat: shared ATHLTH palette, no nested
/// scroll view or material effects. The intake remains the source of truth.
struct ATHLTHCoachChatPlanIntakeCard: View {
    let intake: ATHLTHCoachChatPlanIntake
    let onChange: (ATHLTHCoachChatPlanIntake) -> Void
    let onGenerate: (ATHLTHCoachChatPlanIntake) -> Void

    private func binding<Value>(_ key: WritableKeyPath<ATHLTHCoachChatPlanIntake, Value>) -> Binding<Value> {
        Binding(get: { intake[keyPath: key] }, set: { value in
            var updated = intake
            updated[keyPath: key] = value
            onChange(updated)
        })
    }

    private var canGenerate: Bool {
        !intake.submitted && intake.isValid &&
            intake.startDate >= Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            planSection
            preferencesSection
            if !intake.submitted {
                footer
            } else {
                Label(planText("Form submitted", "Skjema sendt"), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
        .disabled(intake.submitted)
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainEditorialCard(compact: true)
        .tint(ATHLTHTrainDesign.bronze)
        .accessibilityIdentifier("athlth-coach-plan-intake")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 42, height: 42)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(planText("PLAN BUILDER", "PLANOPPSETT"))
                    .font(ATHLTHTrainDesign.cardEyebrow)
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Text(planText("Your training plan", "Din treningsplan"))
                    .font(ATHLTHTrainDesign.cardTitle)
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(planText("Review the choices before Coach creates your plan.",
                              "Tilpass valgene før Coach lager planen."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading(planText("Plan", "Plan"))
            VStack(spacing: 0) {
                choiceMenu(planText("Training goal", "Treningsmål"), symbol: "target",
                           options: ATHLTHCoachChatPlanIntake.Goal.allCases,
                           selection: binding(\.goal), title: { $0.title })
                    .accessibilityIdentifier("athlth-coach-plan-goal")
                separator
                DatePicker(selection: binding(\.startDate), displayedComponents: .date) {
                    fieldLabel(planText("Start date", "Startdato"), symbol: "calendar")
                }
                .font(.subheadline)
                .datePickerStyle(.compact)
                .padding(.horizontal, 11)
                .frame(minHeight: 48)
                .accessibilityIdentifier("athlth-coach-plan-start-date")
                separator
                numberRow(planText("Weeks", "Uker"), symbol: "calendar",
                          value: binding(\.weeks), range: 2...12)
                separator
                numberRow(planText("Workouts per week", "Økter per uke"), symbol: "repeat",
                          value: binding(\.sessionsPerWeek), range: 2...4)
            }
            .modifier(CoachPlanFieldSurface())
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading(planText("Preferences", "Preferanser"))
            VStack(spacing: 0) {
                choiceMenu(planText("Training place", "Treningssted"), symbol: "mappin.and.ellipse",
                           options: ATHLTHCoachChatPlanIntake.Place.allCases,
                           selection: binding(\.place), title: { $0.title })
                separator
                choiceMenu(planText("Experience", "Nivå"), symbol: "chart.bar.xaxis",
                           options: ATHLTHCoachChatPlanIntake.Experience.allCases,
                           selection: binding(\.experience), title: { $0.title })
                if intake.supportsMuscleFocus {
                    separator
                    muscleMenu
                }
            }
            .modifier(CoachPlanFieldSurface())
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { intake.rememberPreferences == true },
                set: { value in
                    var updated = intake
                    updated.rememberPreferences = value
                    onChange(updated)
                }
            )) {
                Text(planText("Remember preferences", "Husk disse preferansene"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 2)
            separator
            if intake.startDate < Calendar.current.startOfDay(for: Date()) {
                Text(planText("Choose today or a future start date.", "Velg i dag eller en fremtidig startdato."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Button { onGenerate(intake) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").accessibilityHidden(true)
                    Text(planText("Create plan", "Lag treningsplan"))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(ATHLTHTrainDesign.ink, in: RoundedRectangle(cornerRadius: 13))
                .opacity(canGenerate ? 1 : 0.45)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            .accessibilityIdentifier("athlth-coach-plan-generate")
        }
    }

    private var muscleMenu: some View {
        Menu {
            Button {
                var updated = intake
                updated.muscleFocus = nil
                onChange(updated)
            } label: {
                Label(planText("General / full body", "Generelt / hele kroppen"),
                      systemImage: intake.activeMuscleFocus.isEmpty ? "checkmark.circle.fill" : "circle")
            }
            ForEach(ATHLTHCoachChatPlanIntake.MuscleFocus.allCases, id: \.self) { group in
                Button {
                    var updated = intake
                    var selected = intake.muscleFocus ?? []
                    if selected.contains(group) { selected.remove(group) }
                    else { selected.insert(group) }
                    updated.muscleFocus = selected.isEmpty ? nil : selected
                    onChange(updated)
                } label: {
                    Label(group.title, systemImage: intake.activeMuscleFocus.contains(group)
                          ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            choiceLabel(planText("Muscle groups", "Muskelgrupper"), symbol: "figure.strengthtraining.traditional",
                        value: intake.muscleFocusTitle)
        }
        .accessibilityLabel(planText("Muscle groups", "Muskelgrupper"))
        .accessibilityValue(intake.muscleFocusTitle)
        .accessibilityIdentifier("athlth-coach-plan-muscles")
    }

    private func choiceMenu<Value: Hashable>(
        _ label: String, symbol: String, options: [Value],
        selection: Binding<Value>, title: @escaping (Value) -> String
    ) -> some View {
        Menu {
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
        } label: {
            choiceLabel(label, symbol: symbol, value: title(selection.wrappedValue))
        }
        .accessibilityLabel(label)
        .accessibilityValue(title(selection.wrappedValue))
    }

    private func choiceLabel(_ label: String, symbol: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 9) {
            fieldIcon(symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func numberRow(_ label: String, symbol: String, value: Binding<Int>,
                           range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack(spacing: 7) {
                fieldLabel(label, symbol: symbol)
                Spacer(minLength: 4)
                Text(value.wrappedValue.formatted())
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ATHLTHTrainDesign.ink)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 48)
        .accessibilityLabel(label)
        .accessibilityValue(value.wrappedValue.formatted())
    }

    private func fieldLabel(_ label: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            fieldIcon(symbol)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHTrainDesign.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var separator: some View {
        Rectangle()
            .fill(ATHLTHTrainDesign.rule.opacity(0.45))
            .frame(height: 1)
            .padding(.horizontal, 11)
            .accessibilityHidden(true)
    }
}

private struct CoachPlanFieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ATHLTHTrainDesign.canvas.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.42), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
    }
}

struct ATHLTHCoachChatPlanCard: View {
    let draft: ATHLTHCoachChatPlanDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: draft.used ? "checkmark.circle" : "calendar")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.used ? planText("PLAN ADDED", "PLAN TATT I BRUK") : planText("PLAN DRAFT", "PLANUTKAST"))
                        .font(ATHLTHTrainDesign.cardEyebrow)
                        .tracking(1)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(draft.program.title)
                        .font(ATHLTHTrainDesign.cardTitle)
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text(draft.program.summary)
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Label("\(draft.intake.weeks) " + planText("weeks", "uker"), systemImage: "calendar")
                Label("\(draft.intake.sessionsPerWeek) " + planText("per week", "per uke"), systemImage: "repeat")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            Divider()
            HStack {
                Text(planText("Open plan", "Åpne plan"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            .frame(minHeight: 32)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainEditorialCard(compact: true)
        .accessibilityElement(children: .combine)
    }
}

struct ATHLTHCoachChatPlanPreview: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    let draft: ATHLTHCoachChatPlanDraft
    let ownerID: UUID
    let onUsed: () -> Void
    @State private var week = 1
    @State private var error: String?
    @State private var saving = false
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(draft.program.title).font(.system(.largeTitle, design: .serif))
                    Text(draft.program.summary).foregroundStyle(.secondary)
                    Label(draft.intake.startDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    HStack {
                        Button { week = max(1, week - 1) } label: { Image(systemName: "chevron.left") }.disabled(week == 1)
                        Spacer()
                        Text(planText("Week", "Uke") + " \(week) / \(draft.program.weeks.count)").font(.headline)
                        Spacer()
                        Button { week = min(draft.program.weeks.count, week + 1) } label: { Image(systemName: "chevron.right") }.disabled(week == draft.program.weeks.count)
                    }
                    if let selected = draft.program.weeks.first(where: { $0.weekNumber == week }) {
                        ForEach(selected.days, id: \.dayIndex) { day in
                            dayView(day)
                        }
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                    Text(planText("Review the plan and adapt exercise and intensity to your ability.", "Gjennomgå planen og tilpass øvelser og intensitet til ditt nivå."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button { confirm = true } label: {
                        Text(draft.used ? planText("Already added", "Allerede tatt i bruk") : planText("Use this plan", "Ta planen i bruk"))
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze).disabled(draft.used || saving)
                }
                .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(ATHLTHTrainDesign.canvas)
            .navigationTitle(planText("Plan draft", "Planutkast"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(planText("Close", "Lukk")) { dismiss() } } }
            .confirmationDialog(planText("Add this plan to your calendar?", "Legge planen til i treningskalenderen?"), isPresented: $confirm, titleVisibility: .visible) {
                Button(planText("Use plan", "Ta i bruk")) { apply() }
            }
        }
    }

    private func dayView(_ day: AIProgramDraftDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.title).font(.headline)
            if day.sessions.isEmpty { Text(planText("Rest day", "Hviledag")).font(.caption).foregroundStyle(.secondary) }
            ForEach(day.sessions.indices, id: \.self) { index in
                let workout = day.sessions[index]
                DisclosureGroup {
                    if let authored = workout.authoredWorkout {
                        ForEach(Array(authored.resolvedWorkoutBlocks.enumerated()), id: \.offset) { item in
                            HStack(alignment: .top) {
                                Text(item.element.title)
                                Spacer()
                                if let sets = item.element.setCount, let reps = item.element.repetitions {
                                    Text("\(sets) × \(reps)").foregroundStyle(.secondary)
                                }
                            }.font(.subheadline)
                        }
                    }
                    if let notes = workout.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(workout.title).font(.subheadline.weight(.semibold))
                        if let minutes = workout.durationMinutes { Text("\(minutes) min").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor private func apply() {
        guard !draft.used, !saving, session.signedIn, session.profile.userID == ownerID else { return }
        saving = true
        defer { saving = false }
        guard draft.intake.startDate >= Calendar.current.startOfDay(for: Date()),
              ATHLTHPlanDraftValidator.issues(in: draft.program, expectedWeeks: draft.intake.weeks,
                maximumSessionsPerWeek: draft.intake.sessionsPerWeek, requireFullWeeks: true,
                requireExecutableWorkouts: true).isEmpty else {
            error = planText("The draft is outdated or invalid. Create a new one in chat.", "Utkastet er utløpt eller ugyldig. Lag et nytt i chatten.")
            return
        }
        let library = exerciseLibrary.selectableExercises
        let allowedIDs = Set(library.map(\.id))
        var plan = draft.program.makeTrainingPlan(ownerID: ownerID, startDate: draft.intake.startDate,
            exerciseLibrary: library)
        let binding = ATHLTHWorkoutExerciseBinding.bind(&plan, library: library)
        guard binding.isReady, plan.weeks.allSatisfy({ week in
            week.days.allSatisfy { day in
                day.sessions.allSatisfy { ATHLTHCoachLibraryGate.hasOnlyLibraryReferences($0, ids: allowedIDs) }
            }
        }) else {
            error = planText("Unresolved library exercises: ", "Øvelser som må kobles til biblioteket: ") + binding.unresolved.prefix(6).joined(separator: ", ")
            return
        }
        guard session.addTrainingPlan(plan, saveToLibrary: true) else {
            error = planText("The plan could not be added. Check overlapping plans.", "Planen kunne ikke legges til. Kontroller overlappende planer.")
            return
        }
        onUsed()
        dismiss()
    }
}
