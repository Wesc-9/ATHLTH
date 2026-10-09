import SwiftUI

/// The second-generation Train plan composer. New UI and navigation;
/// existing plan persistence is intentionally preserved.
struct ATHLTHTrainProgramComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    var onCreated: ((UUID) -> Void)? = nil

    @StateObject private var catalog = TrainingPlanLibraryStore()

    @AppStorage("athlth.planWorkspace.advancedMode")
    private var advancedMode = false

    @State private var step: Step = .identity
    @State private var title = ""
    @State private var weeks = 8
    @State private var customWeeks = false
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var source: Source = .scratch
    @State private var savedPlanID: UUID?
    @State private var catalogPlanID: UUID?
    @State private var focus: TrainingPlanFocus = .generalFitness
    @State private var secondaryFocus: TrainingPlanFocus?
    @State private var goal: TrainingPlanGoalType = .improveFitness
    @State private var goalDetail = ""
    @State private var selectedMuscles: Set<String> = []
    @State private var sessionDays: Set<Int> = [1, 3, 5]
    @State private var sessionsPerWeek = 3
    @State private var autoWeekStructure = false
    @State private var durationPerWorkout = 60
    @State private var equipment = "gym"
    @State private var limitations = ""
    @State private var errorText: String?
    @State private var didResolveDate = false

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.17)
    private let charcoal = Color(red: 0.29, green: 0.28, blue: 0.27)
    private let bronze = Color(red: 0.65, green: 0.52, blue: 0.34)
    private let paper = Color(red: 0.986, green: 0.978, blue: 0.964)
    private let faint = Color(red: 0.954, green: 0.943, blue: 0.923)
    private let border = Color(red: 0.88, green: 0.86, blue: 0.83)

    private enum Step: Int, CaseIterable {
        case identity, source, goals, schedule, confirm
        var number: Int { rawValue + 1 }
    }

    private enum Source: String {
        case scratch, saved, template
    }

    private struct Muscle: Identifiable {
        let id: String
        let name: String
    }

    private let muscles: [Muscle] = [
        .init(id: "biceps", name: "Biceps"),
        .init(id: "triceps", name: "Triceps"),
        .init(id: "chest", name: "Bryst"),
        .init(id: "back", name: "Rygg"),
        .init(id: "shoulders", name: "Skuldre"),
        .init(id: "core", name: "Kjerne"),
        .init(id: "quads", name: "Forside lår"),
        .init(id: "hamstrings", name: "Bakside lår"),
        .init(id: "glutes", name: "Sete"),
        .init(id: "calves", name: "Legger")
    ]

    private var selectedSavedPlan: TrainingPlan? {
        session.planTemplates.first { $0.id == savedPlanID }
    }

    private var selectedCatalogPlan: TrainingPlanCatalogEntry? {
        catalog.entries.first { $0.id == catalogPlanID }
    }

    private var durationWeeks: Int {
        switch source {
        case .scratch: return weeks
        case .saved: return selectedSavedPlan?.weeks.count ?? weeks
        case .template: return selectedCatalogPlan?.durationWeeks ?? weeks
        }
    }

    private var endingDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(durationWeeks * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(startDate: startDate, endDate: endingDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        switch step {
                        case .identity: identityStep
                        case .source: sourceStep
                        case .goals: goalStep
                        case .schedule: scheduleStep
                        case .confirm: confirmationStep
                        }
                    }
                    .frame(maxWidth: 650, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 19)
                    .padding(.top, 20)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.hidden)

                bottomControls
            }
            .background(paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(charcoal)
                }
                ToolbarItem(placement: .principal) {
                    Text("ATHLTH / PLAN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(ink)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await catalog.refresh() }
            .onAppear {
                guard !didResolveDate else { return }
                didResolveDate = true
                startDate = max(
                    startDate,
                    session.suggestedTrainingPlanStartDate
                )
            }
            .onChange(of: sessionsPerWeek) { _, count in
                if sessionDays.count != count {
                    sessionDays = suggestedDays(for: count)
                }
            }
            .alert(tr("Could not create plan", "Kunne ikke opprette planen"),
                   isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var progressHeader: some View {
        VStack(spacing: 13) {
            HStack {
                Text(
                    tr("CREATE YOUR PROGRAM", "BYGG TRENINGSPROGRAM")
                )
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                Spacer()
                Text("\(step.number) / 5")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            .foregroundStyle(charcoal)

            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { position in
                    Capsule()
                        .fill(position <= step.rawValue ? bronze : border)
                        .frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 15)
        .background(.white.opacity(0.82))
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 21) {
            heading(
                number: "01",
                title: tr("Give your plan a direction.", "Gi planen en retning."),
                subtitle: tr(
                    "A name, a period and a starting point. Everything else can be adjusted later.",
                    "Start med navn, varighet og startdato. Du kan endre alle detaljer senere."
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                fieldTitle(tr("Program name", "Navn på treningsplan"))
                TextField(
                    tr("e.g. Stronger upper body", "F.eks. Sterkere overkropp"),
                    text: $title
                )
                .textInputAutocapitalization(.sentences)
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(border, lineWidth: 0.75)
                }
                .accessibilityLabel(tr("Plan name", "Plannavn"))
            }

            VStack(alignment: .leading, spacing: 13) {
                fieldTitle(tr("Duration", "Varighet"))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 86), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach([4, 6, 8, 12, 16], id: \.self) { count in
                        tile(
                            title: "\(count) " + tr("weeks", "uker"),
                            selected: !customWeeks && weeks == count
                        ) {
                            weeks = count
                            customWeeks = false
                        }
                    }
                    tile(title: tr("Custom", "Egendefinert"),
                         selected: customWeeks) {
                        customWeeks = true
                    }
                }
                if customWeeks {
                    Stepper(
                        "\(weeks) " + tr("weeks", "uker"),
                        value: $weeks,
                        in: 1...52
                    )
                    .font(.subheadline.weight(.medium))
                    .tint(ink)
                    .padding(13)
                    .surface(line: border)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldTitle(tr("Start date", "Startdato"))
                DatePicker(
                    tr("Start", "Start"),
                    selection: $startDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(ink)
                .padding(14)
                .surface(line: border)
            }
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading(
                number: "02",
                title: tr("Make it yours.", "Hvordan vil du starte?"),
                subtitle: tr(
                    "Build everything yourself, reuse a saved program or start from a proven template.",
                    "Bygg helt selv, gjenbruk en lagret plan eller tilpass en ferdig treningsmal."
                )
            )
            sourceOption(
                title: tr("Start with a blank plan", "Bygg fra bunnen"),
                subtitle: tr("Complete control, no predefined sessions.",
                             "Helt fri planlegging uten obligatoriske økter."),
                icon: "square.and.pencil",
                selected: source == .scratch
            ) {
                source = .scratch
            }

            sourceOption(
                title: tr("Use a saved plan", "Bruk lagret plan"),
                subtitle: tr("Copy an earlier program without changing the original.",
                             "Kopier et program uten å endre originalen."),
                icon: "bookmark",
                selected: source == .saved
            ) {
                source = .saved
            }
            if source == .saved {
                if session.planTemplates.isEmpty {
                    helperText(tr("No saved plans yet. You can build your first one.",
                                  "Ingen lagrede planer ennå. Du kan bygge din første."))
                } else {
                    ForEach(session.planTemplates) { plan in
                        choiceRow(
                            title: plan.title,
                            detail: "\(plan.weeks.count) " + tr("weeks", "uker"),
                            chosen: savedPlanID == plan.id
                        ) {
                            savedPlanID = plan.id
                        }
                    }
                }
            }

            sourceOption(
                title: tr("Use a training template", "Bruk en treningsmal"),
                subtitle: tr("Select a starting point and personalize it later.",
                             "Velg et utgangspunkt du kan endre senere."),
                icon: "rectangle.stack",
                selected: source == .template
            ) {
                source = .template
            }

            if source == .template {
                ForEach(catalog.entries.prefix(25)) { entry in
                    choiceRow(
                        title: entry.title,
                        detail: "\(entry.durationWeeks) " + tr("weeks", "uker")
                            + " · \(entry.sessionsPerWeek) " + tr("per week", "per uke"),
                        chosen: catalogPlanID == entry.id
                    ) {
                        catalogPlanID = entry.id
                    }
                }
            }

            if source != .scratch {
                helperText(tr(
                    "The selected plan's original duration and workouts are preserved. Your start date will be used for the new copy.",
                    "Den valgte planens varighet og økter bevares i kopien. Din startdato brukes for den nye planen."
                ))
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            heading(
                number: "03",
                title: tr("What drives you?", "Hva vil du oppnå?"),
                subtitle: tr(
                    "Set your primary focus and a concrete goal. This is guidance, not a lock.",
                    "Definer hovedfokus og et mål. Ingenting låses – du kan endre hele planen."
                )
            )

            fieldTitle(tr("Primary focus", "Hovedfokus"))
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(TrainingPlanFocus.allCases) { item in
                    Button {
                        focus = item
                        if secondaryFocus == item { secondaryFocus = nil }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(focus == item ? .white : bronze)
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(focus == item ? .white : ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 77,
                               alignment: .leading)
                        .background(
                            focus == item ? ink : .white,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            fieldTitle(tr("Main goal", "Hva ønsker du å oppnå?"))
            Picker(tr("Goal", "Mål"), selection: $goal) {
                ForEach(TrainingPlanGoalType.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .tint(ink)
            .padding(12)
            .surface(line: border)

            TextField(
                tr("e.g. Stronger biceps, 10K in 45:00",
                   "F.eks. Sterkere biceps eller 10 km på 45 min"),
                text: $goalDetail,
                axis: .vertical
            )
            .lineLimit(2...4)
            .padding(14)
            .surface(line: border)

            if focus == .strength || focus == .hypertrophy
                || focus == .hybrid {
                fieldTitle(tr("Muscle priorities (optional)",
                              "Prioriter muskelgrupper (valgfritt)"))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 99), spacing: 7)],
                    spacing: 7
                ) {
                    ForEach(muscles) { muscle in
                        tile(
                            title: tr(muscle.name, muscle.name),
                            selected: selectedMuscles.contains(muscle.id)
                        ) {
                            if selectedMuscles.contains(muscle.id) {
                                selectedMuscles.remove(muscle.id)
                            } else {
                                selectedMuscles.insert(muscle.id)
                            }
                        }
                    }
                }
            }

            if advancedMode {
                fieldTitle(tr("Secondary focus", "Sekundært fokus"))
                Picker(tr("Secondary focus", "Sekundært fokus"),
                       selection: $secondaryFocus) {
                    Text(tr("None", "Ingen"))
                        .tag(nil as TrainingPlanFocus?)
                    ForEach(TrainingPlanFocus.allCases.filter { $0 != focus }) {
                        item in
                        Text(item.title).tag(item as TrainingPlanFocus?)
                    }
                }
                .tint(ink)
                .padding(12)
                .surface(line: border)

                fieldTitle(tr("Training considerations", "Hensyn under trening"))
                TextField(
                    tr("Optional note about exercise limitations",
                       "Valgfrie hensyn til trening eller øvelser"),
                    text: $limitations,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .padding(13)
                .surface(line: border)
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(
                number: "04",
                title: tr("Shape your training week.", "Bestem treningsuken."),
                subtitle: tr(
                    "Choose the rhythm that fits your life. Individual days can always be edited.",
                    "Velg en rytme som fungerer for deg. Hver dag kan endres senere."
                )
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    fieldTitle(tr("Workouts per week", "Økter per uke"))
                    helperText(tr("You can train multiple times on one day later.",
                                  "Du kan legge flere økter på samme dag senere."))
                }
                Spacer()
                Stepper("\(sessionsPerWeek)",
                        value: $sessionsPerWeek, in: 1...7)
                    .labelsHidden()
                Text("\(sessionsPerWeek)")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 25)
            }
            .padding(14)
            .surface(line: border)

            fieldTitle(tr("Preferred days", "Foretrukne treningsdager"))
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if sessionDays.contains(day) {
                            if sessionDays.count > 1 {
                                sessionDays.remove(day)
                                sessionsPerWeek = sessionDays.count
                            }
                        } else {
                            sessionDays.insert(day)
                            sessionsPerWeek = sessionDays.count
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(dayName(day))
                                .font(.caption2.weight(.semibold))
                            Image(systemName: sessionDays.contains(day)
                                  ? "checkmark" : "minus")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(sessionDays.contains(day) ? .white : ink)
                        .frame(maxWidth: .infinity, minHeight: 55)
                        .background(
                            sessionDays.contains(day) ? ink : .white,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayName(day))
                    .accessibilityAddTraits(
                        sessionDays.contains(day) ? .isSelected : []
                    )
                }
            }

            Toggle(isOn: $autoWeekStructure) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Suggest a weekly structure",
                            "Foreslå grunnstruktur for uken"))
                        .font(.subheadline.weight(.semibold))
                    Text(tr(
                        "Create workout placeholders on selected days. All exercises remain editable.",
                        "Legg inn redigerbare øktplasser på valgte dager. Du velger selv øvelsene."
                    ))
                    .font(.caption)
                    .foregroundStyle(charcoal)
                }
            }
            .tint(bronze)
            .padding(14)
            .surface(line: border)

            if advancedMode {
                VStack(alignment: .leading, spacing: 12) {
                    fieldTitle(tr("Equipment", "Tilgjengelig utstyr"))
                    Picker(tr("Equipment", "Utstyr"), selection: $equipment) {
                        Text(tr("Gym", "Treningssenter")).tag("gym")
                        Text(tr("Home", "Hjemme")).tag("home")
                        Text(tr("Both", "Begge")).tag("both")
                    }
                    .pickerStyle(.segmented)

                    fieldTitle(tr("Minutes per session (estimate)",
                                  "Minutter per økt (estimat)"))
                    Stepper("\(durationPerWorkout) min",
                            value: $durationPerWorkout,
                            in: 15...180,
                            step: 15)
                    .font(.subheadline)
                }
                .padding(15)
                .surface(line: border)
            }

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(bronze)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("AI stays optional", "AI er alltid valgfritt"))
                        .font(.subheadline.weight(.semibold))
                    helperText(tr(
                        "You can ask the coach for suggestions after creating the plan. No changes happen without approval.",
                        "Du kan be coach om forslag etter opprettelsen. Ingen endringer gjøres uten godkjenning."
                    ))
                }
            }
            .padding(15)
            .background(faint, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var confirmationStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            heading(
                number: "05",
                title: tr("Ready to begin?", "Klar til å bygge?"),
                subtitle: tr(
                    "Review the essentials. After saving you'll work week by week.",
                    "Kontroller oppsettet. Etter lagring bygger du videre dag for dag."
                )
            )

            VStack(spacing: 0) {
                summaryRow(tr("Name", "Navn"), value: title)
                Divider().overlay(border)
                summaryRow(tr("Start", "Start"),
                           value: startDate.formatted(date: .abbreviated, time: .omitted))
                Divider().overlay(border)
                summaryRow(tr("Duration", "Varighet"),
                           value: "\(durationWeeks) " + tr("weeks", "uker"))
                Divider().overlay(border)
                summaryRow(tr("Source", "Utgangspunkt"),
                           value: selectedSourceTitle)
                Divider().overlay(border)
                summaryRow(tr("Focus", "Fokus"), value: focus.title)
                Divider().overlay(border)
                summaryRow(tr("Goal", "Mål"),
                           value: goalDetail.isEmpty ? goal.title : goalDetail)
                Divider().overlay(border)
                summaryRow(tr("Weekly sessions", "Økter per uke"),
                           value: "\(sessionDays.count)")
                Divider().overlay(border)
                summaryRow(tr("Detail level", "Detaljnivå"),
                           value: advancedMode ? tr("Advanced", "Avansert") : "Basic")
            }
            .padding(.horizontal, 15)
            .surface(line: border)

            if let conflict = conflictingPlan {
                Label(
                    tr(
                        "The selected dates overlap with \(conflict.title). Change the period before saving.",
                        "Planperioden overlapper med \(conflict.title). Endre datoene før lagring."
                    ),
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.subheadline)
                .foregroundStyle(ink)
                .padding(14)
                .background(faint, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(bronze)
                helperText(tr(
                    "Your original saved plans and workout history will not be changed.",
                    "Tidligere planer og treningshistorikk blir ikke overskrevet."
                ))
            }
            .padding(12)
        }
    }

    private var selectedSourceTitle: String {
        switch source {
        case .scratch: return tr("Blank plan", "Fra bunnen")
        case .saved: return selectedSavedPlan?.title ?? tr("Saved plan", "Lagret plan")
        case .template: return selectedCatalogPlan?.title ?? tr("Template", "Treningsmal")
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 11) {
            if step != .identity {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        step = Step(rawValue: step.rawValue - 1) ?? .identity
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 49, height: 49)
                        .foregroundStyle(ink)
                        .background(faint, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Button {
                if step == .confirm {
                    create()
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        step = Step(rawValue: step.rawValue + 1) ?? .confirm
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Text(step == .confirm
                         ? tr("Create plan", "Opprett treningsplan")
                         : tr("Continue", "Fortsett"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .frame(height: 49)
                .background(ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.45)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(.white)
        .overlay(alignment: .top) {
            Rectangle().fill(border).frame(height: 0.65)
        }
    }

    private var canContinue: Bool {
        switch step {
        case .identity:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .source:
            return source == .scratch ||
                (source == .saved && selectedSavedPlan != nil) ||
                (source == .template && selectedCatalogPlan != nil)
        case .goals:
            return true
        case .schedule:
            return !sessionDays.isEmpty
        case .confirm:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && conflictingPlan == nil && !sessionDays.isEmpty
        }
    }

    private func create() {
        guard canContinue else { return }
        let created: TrainingPlan?

        switch source {
        case .scratch:
            let profile = TrainingPlanBuilderProfile(
                mode: advancedMode ? .advanced : .basic,
                primaryFocus: focus,
                secondaryFocus: advancedMode ? secondaryFocus : nil,
                primaryFocusWeightPercent: advancedMode && secondaryFocus != nil ? 70 : nil,
                goal: goal,
                goalDetail: goalDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : goalDetail,
                competitionDate: nil,
                sessionsPerWeek: sessionDays.count,
                preferredDayIndexes: sessionDays.sorted(),
                injuriesOrLimitations: limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : limitations,
                priorityMuscles: selectedMuscles.sorted(),
                equipmentContext: equipment,
                weeklyTimeBudgetMinutes: durationPerWorkout * sessionDays.count,
                preferredWorkoutKindsByDay: [:]
            )
            created = session.createConfiguredTrainingPlan(
                title: title,
                summary: goalDetail,
                weekCount: weeks,
                startDate: startDate,
                builderProfile: profile,
                seedSuggestedWeek: autoWeekStructure
            )

        case .saved:
            guard let savedPlanID else { return }
            created = session.usePlanTemplate(savedPlanID, startDate: startDate)

        case .template:
            guard let entry = selectedCatalogPlan,
                  let savedTemplate = session.saveCatalogPlanTemplate(entry) else {
                errorText = tr("Could not load template.", "Kunne ikke laste treningsmalen.")
                return
            }
            created = session.usePlanTemplate(savedTemplate.id, startDate: startDate)
        }

        guard let created else {
            errorText = tr(
                "Could not save this training plan. Check for conflicting program dates.",
                "Kunne ikke lagre planen. Sjekk om perioden overlapper en annen plan."
            )
            return
        }

        if source != .scratch {
            let _ = session.updateTrainingPlanMetadata(
                planID: created.id,
                title: title,
                summary: created.summary,
                visibility: .privateOnly,
                tags: created.tags,
                startDate: created.startDate ?? startDate
            )
        }

        onCreated?(created.id)
        dismiss()
    }

    private func suggestedDays(for count: Int) -> Set<Int> {
        switch count {
        case 1: return [1]
        case 2: return [1, 4]
        case 3: return [1, 3, 5]
        case 4: return [1, 2, 4, 6]
        case 5: return [1, 2, 3, 5, 6]
        case 6: return [1, 2, 3, 4, 5, 6]
        default: return Set(1...7)
        }
    }

    private func heading(number: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STEP " + number)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(bronze)
            Text(title)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(charcoal)
                .fixedSize(horizontal: false, vertical: true)
            if step == .goals || step == .schedule {
                HStack {
                    Text(tr("Level of control", "Detaljnivå"))
                        .font(.caption)
                        .foregroundStyle(charcoal)
                    Spacer()
                    Picker("", selection: $advancedMode) {
                        Text("Basic").tag(false)
                        Text(tr("Advanced", "Avansert")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 185)
                }
                .padding(12)
                .surface(line: border)
            }
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
    }

    private func helperText(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(charcoal)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceOption(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(bronze)
                    .frame(width: 37)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(charcoal)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? bronze : border)
            }
            .padding(15)
            .background(selected ? faint : .white,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? bronze.opacity(0.6) : border,
                            lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private func choiceRow(
        title: String,
        detail: String,
        chosen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(charcoal)
                }
                Spacer()
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? bronze : border)
            }
            .foregroundStyle(ink)
            .padding(14)
            .surface(line: border)
        }
        .buttonStyle(.plain)
    }

    private func tile(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : ink)
                .frame(maxWidth: .infinity, minHeight: 43)
                .background(selected ? ink : .white,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? ink : border, lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.caption)
                .foregroundStyle(charcoal)
                .frame(width: 91, alignment: .leading)
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
    }

    private func dayName(_ i: Int) -> String {
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let no = ["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"]
        let idx = min(max(i - 1, 0), 6)
        return tr(en[idx], no[idx])
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

private extension View {
    func surface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(line, lineWidth: 0.7)
            }
    }
}
