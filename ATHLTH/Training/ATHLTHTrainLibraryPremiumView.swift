import SwiftUI

/// A fresh library surface for the rebuilt Train tab.
/// It reads existing saved data but does not reuse the legacy library layout.
struct ATHLTHTrainLibraryPremiumView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    let onOpenPlan: () -> Void
    var onPlanCreated: ((UUID) -> Void)? = nil

    @StateObject private var catalog = TrainingPlanLibraryStore()
    @State private var section: LibrarySection = .plans
    @State private var query = ""
    @State private var exerciseGroup = ""
    @State private var selectedTemplate: TrainingPlan?
    @State private var selectedCatalogPlan: TrainingPlanCatalogEntry?
    @State private var selectedWorkout: PlannedSession?
    @State private var selectedExercise: ExerciseLibraryEntry?
    @State private var showingCreatePlan = false
    @State private var alertMessage: String?

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let secondary = Color(red: 0.46, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let paper = Color(red: 0.98, green: 0.97, blue: 0.95)
    private let line = Color(red: 0.89, green: 0.87, blue: 0.84)

    private enum LibrarySection: String, CaseIterable, Identifiable {
        case plans
        case workouts
        case exercises
        var id: String { rawValue }
        var label: String {
            switch self {
            case .plans: return ATHLTHLocalization.choose(english: "Plans", norwegian: "Planer")
            case .workouts: return ATHLTHLocalization.choose(english: "Workouts", norwegian: "Økter")
            case .exercises: return ATHLTHLocalization.choose(english: "Exercises", norwegian: "Øvelser")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(tr("TRAINING RESOURCES", "DIN TRENINGSSAMLING"))
                    Text(tr("Library", "Bibliotek"))
                        .font(.system(size: 35, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Image(systemName: "books.vertical")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(champagne)
            }

            Text(tr(
                "Everything in one place. Reuse a complete plan, pick a workout, or find your next exercise.",
                "Planer, lagrede økter og øvelser samlet på ett sted – klare for neste treningsprogram."
            ))
            .font(.subheadline)
            .foregroundStyle(secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { item in
                    Button {
                        section = item
                        query = ""
                    } label: {
                        Text(item.label)
                            .font(.caption.weight(section == item ? .semibold : .medium))
                            .foregroundStyle(section == item ? .white : secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                section == item ? ink : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(4)
            .background(
                Color(red: 0.93, green: 0.92, blue: 0.90),
                in: RoundedRectangle(cornerRadius: 14)
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(secondary)
                TextField(searchPrompt, text: $query)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(line, lineWidth: 0.7)
            }

            switch section {
            case .plans: planLibrary
            case .workouts: workoutLibrary
            case .exercises: exerciseLibraryContent
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await catalog.refresh() }
        .sheet(isPresented: $showingCreatePlan) {
            ATHLTHTrainProgramComposerView { planID in
                onPlanCreated?(planID)
                onOpenPlan()
            }
        }
        .sheet(item: $selectedTemplate) { plan in
            templatePreview(plan)
        }
        .sheet(item: $selectedCatalogPlan) { entry in
            catalogPreview(entry)
        }
        .sheet(item: $selectedWorkout) { workout in
            workoutPreview(workout)
        }
        .sheet(item: $selectedExercise) { exercise in
            exercisePreview(exercise)
        }
        .alert(tr("Plan library", "Treningsbibliotek"),
               isPresented: Binding(
                get: { alertMessage != nil },
                set: { shown in if !shown { alertMessage = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var searchPrompt: String {
        switch section {
        case .plans: return tr("Find a plan", "Søk etter treningsplan")
        case .workouts: return tr("Find a workout", "Søk etter økt")
        case .exercises: return tr("Exercise or muscle group", "Øvelse eller muskelgruppe")
        }
    }

    @ViewBuilder
    private var planLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showingCreatePlan = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 37, height: 37)
                        .background(.white.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Create your own plan", "Bygg din egen treningsplan"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Every week and workout is yours to control",
                                "Full kontroll på uker, økter og progresjon"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.74))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .padding(15)
                .background(ink, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            if !session.trainingPlans.isEmpty {
                sectionTitle(tr("MY PROGRAMS", "MINE TRENINGSPROGRAM"))
                ForEach(session.trainingPlans.filter { matches($0.title, $0.summary) }) { plan in
                    Button {
                        onOpenPlan()
                    } label: {
                        planRow(
                            title: plan.title,
                            detail: tr("\(plan.weeks.count) weeks · Scheduled",
                                       "\(plan.weeks.count) uker · Planlagt"),
                            icon: "calendar.badge.clock"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !session.planTemplates.isEmpty {
                sectionTitle(tr("SAVED PLANS", "LAGREDE PLANER"))
                ForEach(session.planTemplates.filter { matches($0.title, $0.summary) }) { plan in
                    Button { selectedTemplate = plan } label: {
                        planRow(
                            title: plan.title,
                            detail: tr("\(plan.weeks.count) weeks · Reusable",
                                       "\(plan.weeks.count) uker · Klar for gjenbruk"),
                            icon: "bookmark"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !catalog.entries.isEmpty {
                sectionTitle(tr("TRAINING TEMPLATES", "FERDIGE TRENINGSMALER"))
                ForEach(catalog.entries.filter {
                    matches($0.title, $0.summary, $0.categoryTitle)
                }.prefix(30)) { entry in
                    Button { selectedCatalogPlan = entry } label: {
                        planRow(
                            title: entry.title,
                            detail: "\(entry.durationWeeks) " + tr("weeks", "uker")
                                + " · \(entry.sessionsPerWeek) " + tr("sessions/week", "økter/uke"),
                            icon: "square.stack.3d.up"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var workoutLibrary: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(tr("SAVED WORKOUTS", "LAGREDE ØKTER"))
            if session.savedWorkoutTemplates.isEmpty && runningLibrary.allTemplates.isEmpty {
                emptySection(
                    tr("No saved workouts yet", "Ingen lagrede økter ennå"),
                    tr("Workouts you save can be reused in your training plan.",
                       "Økter du lagrer skal kunne brukes igjen i treningsplanen.")
                )
            }
            ForEach(session.savedWorkoutTemplates.filter { matches($0.title) }) { workout in
                Button { selectedWorkout = workout } label: {
                    planRow(
                        title: workout.title,
                        detail: workout.kind.title + workout.durationMinutes.map {
                            " · \($0) min"
                        }.orEmpty,
                        icon: workout.kind.systemImage
                    )
                }
                .buttonStyle(.plain)
            }
            if !runningLibrary.allTemplates.isEmpty {
                sectionTitle(tr("RUNNING WORKOUTS", "LØPEØKTER"))
                ForEach(runningLibrary.allTemplates.filter { matches($0.title) }.prefix(30)) { workout in
                    HStack(spacing: 13) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(champagne)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title)
                                .font(.subheadline.weight(.medium))
                            Text(tr("Running workout template", "Lagret løpeprogram"))
                                .font(.caption)
                                .foregroundStyle(secondary)
                        }
                        Spacer()
                        Image(systemName: "bookmark")
                            .foregroundStyle(secondary)
                    }
                    .padding(14)
                    .librarySurface(line: line)
                }
            }
            Button(action: onOpenPlan) {
                Label(tr("Add a workout in your plan", "Legg til økt i treningsplan"),
                      systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(paper, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var exerciseLibraryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(tr("EXERCISE INDEX", "ØVELSESBIBLIOTEK"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(tr("All", "Alle"), group: "")
                    ForEach(ExerciseMuscleGroup.allCases) { muscle in
                        filterChip(muscle.title, group: muscle.rawValue)
                    }
                }
            }

            let filteredExercises = exerciseLibrary.allExercises.filter { item in
                let nameMatch = matches(item.name, item.canonicalName,
                                        item.bodyPart ?? "", item.category ?? "")
                let muscleMatch = exerciseGroup.isEmpty
                    || item.bodyPart?.localizedCaseInsensitiveContains(exerciseGroup) == true
                    || item.category?.localizedCaseInsensitiveContains(exerciseGroup) == true
                return nameMatch && muscleMatch
            }

            if filteredExercises.isEmpty {
                emptySection(
                    tr("No matching exercises", "Fant ingen øvelser"),
                    tr("Try a different name or muscle group.",
                       "Prøv et annet navn eller en muskelgruppe.")
                )
            }

            ForEach(filteredExercises.prefix(65)) { entry in
                Button { selectedExercise = entry } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(champagne)
                            .frame(width: 36, height: 36)
                            .background(paper, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(entry.bodyPart.map {
                                exerciseLibrary.localizedBodyPartTitle($0)
                            } ?? entry.category ?? tr("Exercise", "Øvelse"))
                            .font(.caption)
                            .foregroundStyle(secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(secondary)
                    }
                    .padding(12)
                    .librarySurface(line: line)
                }
                .buttonStyle(.plain)
            }

            if filteredExercises.count > 65 {
                Text(tr("Use search to narrow down more exercises.",
                        "Bruk søk eller filter for å finne flere øvelser."))
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        }
    }

    private func templatePreview(_ plan: TrainingPlan) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    previewHeading(plan.title, subtitle: tr(
                        "Saved plan · \(plan.weeks.count) weeks",
                        "Lagret plan · \(plan.weeks.count) uker"
                    ))
                    Text(plan.summary)
                        .font(.subheadline)
                        .foregroundStyle(secondary)
                    ForEach(plan.weeks.prefix(2)) { week in
                        Text(tr("Week \(week.weekNumber)", "Uke \(week.weekNumber)"))
                            .font(.headline)
                        ForEach(week.days) { day in
                            ForEach(day.sessions) { workout in
                                planRow(
                                    title: workout.title,
                                    detail: workout.kind.title,
                                    icon: workout.kind.systemImage
                                )
                            }
                        }
                    }
                    Button {
                        let created = session.usePlanTemplate(
                            plan.id,
                            startDate: session.suggestedTrainingPlanStartDate
                        )
                        if created != nil {
                            selectedTemplate = nil
                            onOpenPlan()
                        } else {
                            alertMessage = tr(
                                "The selected dates conflict with another plan. Change your schedule before starting.",
                                "Datoene kolliderer med en annen plan. Endre planperioden før du starter."
                            )
                        }
                    } label: {
                        primaryLabel(tr("Use a copy of this plan", "Bruk en kopi av denne planen"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Saved plan", "Lagret plan"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func catalogPreview(_ entry: TrainingPlanCatalogEntry) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewHeading(entry.title, subtitle: entry.categoryTitle)
                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(secondary)
                    HStack {
                        Label("\(entry.durationWeeks) " + tr("weeks", "uker"),
                              systemImage: "calendar")
                        Spacer()
                        Label("\(entry.sessionsPerWeek) " + tr("per week", "per uke"),
                              systemImage: "figure.run")
                    }
                    .font(.caption)
                    .foregroundStyle(secondary)
                    Text(entry.goal)
                        .font(.subheadline)
                    Button {
                        let saved = session.saveCatalogPlanTemplate(entry)
                        if saved != nil {
                            selectedCatalogPlan = nil
                            section = .plans
                        } else {
                            alertMessage = tr(
                                "Could not save this plan.",
                                "Kunne ikke lagre treningsplanen."
                            )
                        }
                    } label: {
                        primaryLabel(tr("Save to my plans", "Lagre i mine planer"))
                    }
                    .buttonStyle(.plain)
                    Text(tr("You can personalize the saved plan before starting it.",
                            "Du kan tilpasse den lagrede planen før du starter."))
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
                .padding(20)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Plan template", "Treningsmal"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func workoutPreview(_ workout: PlannedSession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    previewHeading(workout.title, subtitle: workout.kind.title)
                    if let minutes = workout.durationMinutes {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(.subheadline)
                    }
                    ForEach(workout.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.embeddedExercise.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(exercise.compactTargetSummary)
                                .font(.caption)
                                .foregroundStyle(secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .librarySurface(line: line)
                    }
                    Button {
                        selectedWorkout = nil
                        onOpenPlan()
                    } label: {
                        primaryLabel(tr("Open my training plan", "Åpne treningsplanen"))
                    }
                    .buttonStyle(.plain)
                    Text(tr("Choose a day in the plan editor to reuse this workout.",
                            "Velg en dag i planeditoren for å bruke økten igjen."))
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
                .padding(20)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Saved workout", "Lagret økt"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func exercisePreview(_ entry: ExerciseLibraryEntry) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    previewHeading(entry.name, subtitle: entry.bodyPart ?? "")
                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(secondary)
                    }
                    if !entry.tips.isEmpty {
                        sectionTitle(tr("TECHNIQUE", "TEKNIKK"))
                        ForEach(entry.tips.prefix(8), id: \.self) { tip in
                            Label(tip, systemImage: "checkmark")
                                .font(.subheadline)
                        }
                    }
                    Button {
                        selectedExercise = nil
                        onOpenPlan()
                    } label: {
                        primaryLabel(tr("Add through plan editor", "Legg til gjennom planeditor"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Exercise", "Øvelse"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func filterChip(_ text: String, group: String) -> some View {
        Button {
            exerciseGroup = group
        } label: {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(exerciseGroup == group ? .white : ink)
                .padding(.horizontal, 12)
                .frame(height: 33)
                .background(
                    exerciseGroup == group ? ink : .white,
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(line, lineWidth: exerciseGroup == group ? 0 : 0.6)
                }
        }
        .buttonStyle(.plain)
    }

    private func planRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(champagne)
                .frame(width: 37, height: 37)
                .background(paper, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(secondary)
        }
        .padding(14)
        .librarySurface(line: line)
    }

    private func previewHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            eyebrow(subtitle.uppercased())
            Text(title)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        HStack {
            Spacer()
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "arrow.right")
        }
        .foregroundStyle(.white)
        .padding(15)
        .background(ink, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ title: String) -> some View {
        eyebrow(title).padding(.top, 4)
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(champagne)
    }

    private func emptySection(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 20, weight: .regular, design: .serif))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .librarySurface(line: line)
    }

    private func matches(_ texts: String...) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return texts.contains { $0.localizedCaseInsensitiveContains(term) }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

private extension View {
    func librarySurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(line, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.03), radius: 8, y: 3)
    }
}
