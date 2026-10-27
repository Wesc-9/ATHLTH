import SwiftUI

/// One library for exercises AND full workout recipes. Used only by the
/// Advanced day-by-day builder; all data comes from existing stores.
struct ATHLTHAdvancedPlanAddContentView: View {
    enum Kind: String, CaseIterable {
        case exercise, workout
    }
    enum Origin: String, CaseIterable {
        case all, favorites, mine, athlth
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exercises: ExerciseLibraryStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var recents: LibraryRecentsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var running: RunningWorkoutLibraryStore
    @StateObject private var catalog = WorkoutTemplateCatalogStore()

    let initialKind: Kind
    let phase: WorkoutPhaseKind
    let onExercise: ([WorkoutTemplateBlock]) -> Void
    let onWorkout: (PlannedSession) -> Void

    @State private var kind: Kind = .exercise
    @State private var origin: Origin = .all
    @State private var search = ""
    @State private var muscle: String? = nil
    @State private var selectedExerciseID: UUID?
    @State private var showingCustomExercise = false

    private let gold = ATHLTHTrainDesign.bronze
    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let canvas = ATHLTHTrainDesign.canvas

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var availableExercises: [ExerciseLibraryEntry] {
        exercises.search(query: search, bodyPart: muscle)
            .filter { entry in
                switch origin {
                case .all: return true
                case .favorites:
                    return favorites.isFavorite(.exercise, itemID: entry.id.uuidString)
                case .mine: return entry.source == .custom
                case .athlth: return entry.source != .custom
                }
            }
    }

    private struct WorkoutChoice: Identifiable {
        let id: String
        let session: PlannedSession
        let mine: Bool
        let favoriteID: String
        var title: String { session.title }
    }

    private var workouts: [WorkoutChoice] {
        let personal = session.savedWorkoutTemplates.map {
            WorkoutChoice(id: "saved-" + $0.id.uuidString, session: $0,
                          mine: true, favoriteID: $0.id.uuidString)
        }
        let runs = running.allTemplates.map { item in
            WorkoutChoice(id: "run-" + item.id.uuidString,
                          session: item.plannedSession(),
                          mine: !item.isBuiltIn, favoriteID: item.id.uuidString)
        }
        let builtIn = catalog.entries.map { item in
            WorkoutChoice(id: "catalog-" + item.id.uuidString,
                          session: item.plannedSession(),
                          mine: false, favoriteID: item.id.uuidString)
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (personal + runs + builtIn).filter { item in
            let sourceMatches: Bool
            switch origin {
            case .all: sourceMatches = true
            case .mine: sourceMatches = item.mine
            case .athlth: sourceMatches = !item.mine
            case .favorites:
                sourceMatches = favorites.isFavorite(.workout, itemID: item.favoriteID)
            }
            return sourceMatches &&
                (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    Picker(tr("Content", "Innhold"), selection: $kind) {
                        Text(tr("Exercises", "Øvelser")).tag(Kind.exercise)
                        Text(tr("Workouts", "Treningsøkter")).tag(Kind.workout)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(secondary)
                        TextField(tr("Search exercises or workouts",
                                     "Søk etter øvelser eller treningsøkter"), text: $search)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel(tr("Clear search", "Tøm søk"))
                        }
                    }
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            originChip(.all, tr("All", "Alle"))
                            originChip(.favorites, tr("Favorites", "Favoritter"))
                            originChip(.mine, tr("Mine", "Mine"))
                            originChip(.athlth, "ATHLTH")
                        }
                    }
                    if kind == .exercise {
                        exerciseContent
                    } else {
                        workoutContent
                    }
                }
                .padding(15)
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle(tr("Add", "Legg til"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if kind == .exercise {
                        Button {
                            showingCustomExercise = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(tr("Create exercise", "Opprett øvelse"))
                    }
                }
            }
            .navigationDestination(item: $selectedExerciseID) { exerciseID in
                if let item = exercises.allExercises.first(where: { $0.id == exerciseID }) {
                    ATHLTHAdvancedExerciseConfigurationView(entry: item, phase: phase) { blocks in
                        onExercise(blocks)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCustomExercise) {
                CustomExerciseEditorView(onSaved: { entry in
                    showingCustomExercise = false
                    selectedExerciseID = entry.id
                })
            }
            .onAppear { kind = initialKind }
            .task {
                async let a: Void = exercises.refresh()
                async let b: Void = favorites.refresh()
                async let c: Void = catalog.refresh()
                _ = await (a,b,c)
            }
        }
    }

    private func originChip(_ value: Origin, _ title: String) -> some View {
        Button { origin = value } label: {
            Text(title)
                .font(.system(size: 12, weight: origin == value ? .semibold : .regular))
                .foregroundStyle(origin == value ? .white : ink)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(origin == value ? gold : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(origin == value ? .isSelected : [])
    }

    private var exerciseContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
                    muscleChoice(nil, "All", "square.grid.2x2")
                    muscleChoice("Chest", tr("Upper body", "Overkropp"), "figure.strengthtraining.traditional")
                    muscleChoice("Quads", tr("Lower body", "Underkropp"), "figure.walk")
                    muscleChoice("Core", tr("Core", "Kjerne"), "figure.core.training")
                    muscleChoice("Back", tr("Back", "Rygg"), "figure.rower")
                    muscleChoice("Shoulders", tr("Shoulders", "Skuldre"), "dumbbell")
                }
            }
            Text(tr("Quick picks", "Rasktvalg"))
                .font(.system(size: 19, weight: .semibold, design: .serif))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(availableExercises.prefix(6))) { item in
                        Button {
                            selectedExerciseID = item.id
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                ExerciseArtwork(entry: item, size: 99)
                                Text(exercises.localizedExerciseName(item))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ink)
                                    .lineLimit(2)
                                    .frame(width: 99, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text(tr("All exercises", "Alle øvelser"))
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                Spacer()
                Text("\(availableExercises.count)")
                    .font(.caption).foregroundStyle(secondary)
            }
            if availableExercises.isEmpty {
                ContentUnavailableView(tr("No exercises", "Ingen øvelser"),
                                       systemImage: "magnifyingglass",
                                       description: Text(tr("Try another filter", "Prøv et annet filter")))
            }
            ForEach(availableExercises.prefix(120)) { item in
                Button { selectedExerciseID = item.id } label: {
                    HStack(spacing: 11) {
                        ExerciseArtwork(entry: item, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercises.localizedExerciseName(item))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                            Text([item.bodyPart.map(exercises.localizedBodyPartTitle),
                                  item.exercise.equipment.first.map(exercises.localizedEquipmentTitle)]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(gold)
                    }
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func muscleChoice(_ value: String?, _ name: String, _ symbol: String) -> some View {
        Button { muscle = value } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(muscle == value ? .white : gold)
                    .frame(width: 43, height: 43)
                    .background(muscle == value ? gold : .white, in: Circle())
                Text(name).font(.system(size: 10)).foregroundStyle(secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var workoutContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("Saved and ready-made workouts", "Lagrede og ferdige treningsøkter"))
                .font(.system(size: 19, weight: .semibold, design: .serif))
            if workouts.isEmpty {
                ContentUnavailableView(tr("No workouts", "Ingen treningsøkter"),
                                       systemImage: "rectangle.stack",
                                       description: Text(tr("Try another filter", "Prøv et annet filter")))
            }
            ForEach(workouts) { item in
                Button {
                    onWorkout(item.session)
                    dismiss()
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.session.kind.systemImage)
                            .font(.system(size: 20))
                            .foregroundStyle(gold)
                            .frame(width: 51, height: 51)
                            .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.mine ? tr("Your workout", "Din treningsøkt") :
                                    tr("ATHLTH library", "ATHLTH-bibliotek"))
                                .font(.caption2).foregroundStyle(secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(gold)
                    }
                    .foregroundStyle(ink)
                    .padding(9)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Real per-exercise configuration, not a static detail card.
/// The returned WorkoutTemplateBlock is persisted in the planned day's recipe.
struct ATHLTHAdvancedExerciseConfigurationView: View {
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @Environment(\.dismiss) private var dismiss
    let entry: ExerciseLibraryEntry
    let phase: WorkoutPhaseKind
    let onAdd: ([WorkoutTemplateBlock]) -> Void
    private struct EditableSet: Identifiable {
        let id = UUID()
        var weight: Double = 0
        var repetitions: Int = 10
    }
    @State private var exerciseSets: [EditableSet] = Array(repeating: EditableSet(), count: 4).map { _ in EditableSet() }
    @State private var restSeconds = 120
    @State private var notes = ""
    private let gold = ATHLTHTrainDesign.bronze
    private let secondary = ATHLTHTrainDesign.secondary

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ExerciseArtwork(entry: entry, size: 370)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()
                HStack(spacing: 10) {
                    ExerciseArtwork(entry: entry, size: 51)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(library.localizedExerciseName(entry))
                            .font(.system(size: 19, weight: .semibold, design: .serif))
                        Text([entry.bodyPart.map(library.localizedBodyPartTitle),
                              entry.exercise.equipment.first.map(library.localizedEquipmentTitle)]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Label(tr("Change exercise", "Bytt øvelse"),
                              systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(gold)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 32)
                            .background(ATHLTHTrainDesign.paleGold.opacity(0.55),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                Text(tr("Sets and reps", "Sett og reps"))
                    .font(.headline)
                ForEach(exerciseSets.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 25, height: 31)
                            .background(ATHLTHTrainDesign.paleGold, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Weight (kg)", "Vekt (kg)"))
                                .font(.system(size: 9)).foregroundStyle(secondary)
                            TextField("0", value: $exerciseSets[index].weight, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("Reps", "Reps"))
                                .font(.system(size: 9)).foregroundStyle(secondary)
                            TextField("10", value: $exerciseSets[index].repetitions,
                                      format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            guard exerciseSets.count > 1 else { return }
                            exerciseSets.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption).foregroundStyle(secondary)
                                .frame(width: 28, height: 42)
                        }
                        .accessibilityLabel(tr("Remove set", "Fjern sett"))
                    }
                    .frame(minHeight: 48)
                }
                Button {
                    guard exerciseSets.count < 20 else { return }
                    if let last = exerciseSets.last {
                        exerciseSets.append(EditableSet(weight: last.weight,
                                                        repetitions: last.repetitions))
                    }
                } label: {
                    Label(tr("Add set", "Legg til sett"), systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(gold)
                        .frame(maxWidth: .infinity, minHeight: 35)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.45),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Divider()
                Stepper(value: $restSeconds, in: 0...600, step: 15) {
                    Label(tr("Rest", "Hviletid") + ": \(restSeconds) sek",
                          systemImage: "timer")
                }
                Text(tr("Notes (optional)", "Notater (valgfritt)"))
                    .font(.subheadline.weight(.medium))
                TextField(tr("Add notes", "Legg til notater"), text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(16)
        }
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .navigationTitle(tr("Add exercise", "Legg til øvelse"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(.exercise, itemID: entry.id.uuidString,
                        title: library.localizedExerciseName(entry))
                } label: {
                    Image(systemName: favorites.isFavorite(.exercise,
                          itemID: entry.id.uuidString) ? "heart.fill" : "heart")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                guard !exerciseSets.isEmpty else { return }
                let rows = exerciseSets.map {
                    (reps: max(1, min($0.repetitions, 100)),
                     weight: $0.weight.isFinite && $0.weight > 0 ? $0.weight : nil)
                }
                let uniform = rows.allSatisfy {
                    $0.reps == rows[0].reps && $0.weight == rows[0].weight
                }
                let payload: [WorkoutTemplateBlock] = {
                    func block(_ row: (reps: Int, weight: Double?), index: Int) -> WorkoutTemplateBlock {
                        var value = WorkoutTemplateBlock(
                            sequence: index, kind: .exercise,
                            title: library.localizedExerciseName(entry),
                            exerciseSlug: entry.sourceIdentifier,
                            distanceMeters: nil, repetitions: row.reps,
                            durationSeconds: nil,
                            targetWeightKilograms: row.weight,
                            loadNote: nil, notes: notes.isEmpty ? nil : notes,
                            phase: phase
                        )
                        value.exerciseID = entry.id
                        if entry.source == .custom && entry.exercise.isVisibleOutsideOwnerLibrary {
                            value.exerciseSnapshot =
                                ATHLTHExerciseReferenceResolver.shareableSnapshot(entry.exercise)
                        }
                        return value
                    }
                    if uniform {
                        var one = block(rows[0], index: 1)
                        one.setCount = rows.count
                        one.restBetweenSetsSeconds = Double(restSeconds)
                        return [one]
                    }
                    var all: [WorkoutTemplateBlock] = []
                    for index in rows.indices {
                        var set = block(rows[index], index: all.count + 1)
                        set.setCount = 1
                        all.append(set)
                        if index < rows.count - 1 && restSeconds > 0 {
                            all.append(WorkoutTemplateBlock(
                                sequence: all.count + 1, kind: .rest,
                                title: tr("Between sets", "Mellom sett"),
                                exerciseSlug: nil, distanceMeters: nil,
                                repetitions: nil, durationSeconds: Double(restSeconds),
                                targetWeightKilograms: nil, loadNote: nil,
                                notes: nil, phase: .recovery
                            ))
                        }
                    }
                    return all
                }()
                onAdd(payload)
            } label: {
                Label(tr("Add exercise", "Legg til øvelse"),
                      systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .background(gold.gradient, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(ATHLTHTrainDesign.canvas)
        }
    }
}
