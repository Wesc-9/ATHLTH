import SwiftUI
import Supabase
import UIKit

enum StrengthAIWorkoutGoal:
    String,
    Codable,
    CaseIterable,
    Identifiable
{
    case general
    case strength
    case hypertrophy
    case endurance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return ATHLTHLocalization.choose(
                english: "Balanced",
                norwegian: "Balansert"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .hypertrophy:
            return ATHLTHLocalization.choose(
                english: "Muscle growth",
                norwegian: "Muskelvekst"
            )
        case .endurance:
            return ATHLTHLocalization.choose(
                english: "Muscular endurance",
                norwegian: "Muskelutholdenhet"
            )
        }
    }
}

private struct StrengthAIExerciseCandidate:
    Encodable,
    Hashable
{
    let exerciseID: UUID
    let name: String
    let bodyPart: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let category: String?
    let difficulty: String?
}

private struct StrengthAIRecentExercise:
    Encodable,
    Hashable
{
    let name: String
    let primaryMuscles: [String]
    let completedSets: Int
}

private struct StrengthAIRecentWorkout:
    Encodable,
    Hashable
{
    let title: String
    let daysAgo: Int
    let exercises: [StrengthAIRecentExercise]
}

private struct StrengthAIExerciseRequest:
    Encodable
{
    let goal: String
    let durationMinutes: Int
    let exerciseCount: Int
    let focusBodyPart: String?
    let focusBodyParts: [String]?
    let personalize: Bool
    let language: String
    let existingExerciseIDs: [UUID]
    let existingExerciseNames: [String]
    let recentWorkouts: [StrengthAIRecentWorkout]
    let candidates: [StrengthAIExerciseCandidate]
}

struct StrengthAIExerciseSuggestion:
    Codable,
    Hashable,
    Identifiable
{
    var id: UUID { exerciseID }

    let exerciseID: UUID
    let sets: Int
    let reps: Int
    let restSeconds: Int
    let targetRPE: Double?
    let reason: String
}

struct StrengthAIExercisePlan:
    Codable,
    Hashable
{
    let title: String
    let summary: String
    let estimatedMinutes: Int
    let exercises: [StrengthAIExerciseSuggestion]
}

private struct StrengthAIServiceErrorPayload: Decodable {
    let error: String?
    let code: String?
}

@MainActor
private final class StrengthAIExerciseService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func generate(
        _ request: StrengthAIExerciseRequest
    ) async throws -> StrengthAIExercisePlan {
        try await client.functions.invoke(
            "generate-strength-session",
            options: FunctionInvokeOptions(
                body: request
            )
        )
    }
}

struct StrengthAIExercisePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseLibrary:
        ExerciseLibraryStore

    let existingExercises: [PlannedExercise]
    let recentWorkouts: [StrengthWorkoutLog]
    /// Quick mode shows one reviewed recommendation, without the large planner.
    var quickSuggestion: Bool = false
    let onApply: ([PlannedExercise]) -> Void

    @State private var goal:
        StrengthAIWorkoutGoal = .general
    @State private var durationMinutes = 45
    @State private var exerciseCount = 5
    @State private var focusBodyParts: Set<String> = []
    @State private var personalize = true
    @State private var sourceFilter: StrengthAIExerciseSourceFilter = .library
    @State private var equipmentFilter: String?
    @State private var editedSuggestions: [StrengthAIExerciseSuggestion] = []
    @State private var replacingSuggestion: StrengthAIExerciseSuggestion?
    @State private var inspectingEntry: ExerciseLibraryEntry?
    @State private var showingLibrary = false

    private let ink = Color(red: 0.18, green: 0.19, blue: 0.21)
    private let accent = Color(red: 0.57, green: 0.47, blue: 0.37)
    private let separator = Color(red: 0.90, green: 0.89, blue: 0.87)
    private let canvas = Color(red: 0.976, green: 0.972, blue: 0.966)
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var plan:
        StrengthAIExercisePlan?

    private let service =
        StrengthAIExerciseService()

    private var availableBodyParts: [String] {
        exerciseLibrary.bodyParts
    }

    private var existingIDs: Set<UUID> {
        Set(existingExercises.compactMap(\.exerciseID))
    }

    private var candidateEntries: [ExerciseLibraryEntry] {
        let available = StrengthAIExerciseSelectionPolicy.available(
            from: exerciseLibrary.selectableExercises,
            excluding: existingIDs,
            source: sourceFilter,
            focuses: Array(focusBodyParts),
            equipment: equipmentFilter
        )
        // With multiple focus groups, a plain alphabetical prefix can
        // accidentally fill all 80 AI candidates from just one muscle.
        // Reserve equal space for each selected group first, then fill any
        // remaining slots without duplicating IDs.
        guard focusBodyParts.count > 1 else {
            return Array(available.prefix(80))
        }
        var result: [ExerciseLibraryEntry] = []
        var included = Set<UUID>()
        let targetGroups = focusBodyParts.sorted()
        let reservation = max(1, 80 / targetGroups.count)
        for group in targetGroups {
            let canonical = ExerciseLibraryStore.canonicalMuscleFilter(group)
            let matches = available.filter { entry in
                ([entry.bodyPart].compactMap { $0 } +
                 entry.exercise.primaryMuscles +
                 entry.exercise.secondaryMuscles).contains {
                    ExerciseLibraryStore.canonicalMuscleFilter($0) == canonical
                }
            }
            for candidate in matches.prefix(reservation)
                where included.insert(candidate.id).inserted {
                result.append(candidate)
            }
        }
        for candidate in available
            where result.count < 80 && included.insert(candidate.id).inserted {
            result.append(candidate)
        }
        return Array(result.prefix(80))
    }

    private var availableEquipment: [String] {
        let matching = StrengthAIExerciseSelectionPolicy.available(
            from: exerciseLibrary.selectableExercises,
            excluding: existingIDs,
            source: sourceFilter,
            focuses: Array(focusBodyParts),
            equipment: nil
        )
        return Array(Set(matching.flatMap { $0.exercise.equipment }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var activeSuggestions: [StrengthAIExerciseSuggestion] {
        editedSuggestions
    }

    /// Only exact UUID matches from the current source/focus/equipment
    /// allow-list may be displayed and subsequently saved.
    private var resolvedSuggestions:
        [(StrengthAIExerciseSuggestion, ExerciseLibraryEntry)] {
        let byID = Dictionary(
            uniqueKeysWithValues: candidateEntries.map { ($0.id, $0) }
        )
        var seen = Set<UUID>()
        return activeSuggestions.compactMap { suggestion in
            guard !seen.contains(suggestion.exerciseID),
                  let entry = byID[suggestion.exerciseID] else {
                return nil
            }
            seen.insert(suggestion.exerciseID)
            return (suggestion, entry)
        }
    }

    private var availableReplacements: [ExerciseLibraryEntry] {
        let used = Set(editedSuggestions.map(\.exerciseID))
        return candidateEntries.filter { !used.contains($0.id) }
    }

    private var hasEnoughExercises: Bool {
        candidateEntries.count >= (quickSuggestion ? 1 : exerciseCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if quickSuggestion {
                        Text(ATHLTHLocalization.choose(
                            english: "One exercise based on your current session, trained muscle groups and previous workouts.",
                            norwegian: "Én øvelse valgt ut fra dagens økt, muskelgrupper og treningshistorikk."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if plan == nil {
                        introCard
                        setupCard
                    }

                    if let errorMessage {
                        errorCard(
                            errorMessage
                        )
                    }

                    if plan != nil {
                        if quickSuggestion {
                            singleSuggestionCard
                        } else {
                            resultCard
                        }
                    }

                    if plan == nil || !quickSuggestion {
                        generateButton
                    }
                }
                .padding(16)
                .padding(.bottom, 26)
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: quickSuggestion
                        ? "ATHLTH Coach recommends"
                        : "AI exercise picker",
                    norwegian: quickSuggestion
                        ? "Anbefalt av ATHLTH Coach"
                        : "AI velger øvelser"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents(
            quickSuggestion ? [.medium, .large] : [.large]
        )
        .task {
            if quickSuggestion && plan == nil && !isGenerating {
                generate()
            }
        }
        .sheet(item: $replacingSuggestion) { target in
            StrengthAIExerciseReplacementPicker(choices: availableReplacements) {
                replacement in
                replace(target.exerciseID, with: replacement)
            }
        }
        .sheet(item: $inspectingEntry) { entry in
            NavigationStack {
                ExerciseDetailView(entry: entry, selectionTitle: nil, onSelect: nil)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) { inspectingEntry = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingLibrary) {
            NavigationStack {
                ExerciseLibraryView(
                    source: sourceFilter == .mine ? .mine : .library,
                    selectionTitle: nil,
                    onSelect: nil
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Done", norwegian: "Ferdig"
                        )) { showingLibrary = false }
                    }
                }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 45, height: 45)
                    .background(canvas, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Build a workout with ATHLTH",
                        norwegian: "La ATHLTH bygge økten"
                    ))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ink)

                    Text(ATHLTHLocalization.choose(
                        english: "Only exercises already in the library you select.",
                        norwegian: "Kun øvelser som finnes i biblioteket du velger."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(separator)

            HStack(spacing: 10) {
                Label(
                    sourceFilter.title,
                    systemImage: "books.vertical"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
                Spacer(minLength: 4)
                Button {
                    showingLibrary = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Open library", norwegian: "Åpne bibliotek"
                        ),
                        systemImage: "arrow.up.right"
                    )
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .tint(accent)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(separator))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ATHLTHLocalization.choose(
                    english: "Set up your workout", norwegian: "Tilpass økten"
                ))
                .font(.title3.weight(.semibold))
                .foregroundStyle(ink)

                Text(ATHLTHLocalization.choose(
                    english: "Choose the criteria. Review every exercise before adding it.",
                    norwegian: "Velg kriterier. Du godkjenner alle øvelsene før de legges til."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(ATHLTHLocalization.choose(
                    english: "EXERCISE SOURCE", norwegian: "ØVELSESKILDE"
                ))
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

                Picker(ATHLTHLocalization.choose(
                    english: "Exercise source", norwegian: "Velg øvelseskilde"
                ), selection: $sourceFilter) {
                    ForEach(StrengthAIExerciseSourceFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("athlth-ai-library-source")
            }

            Divider()

            settingsRow(title: ATHLTHLocalization.choose(
                english: "Goal", norwegian: "Mål"
            )) {
                Picker("", selection: $goal) {
                    ForEach(StrengthAIWorkoutGoal.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(ink)
            }

            Divider()

            settingsRow(title: ATHLTHLocalization.choose(
                english: "Time", norwegian: "Tid"
            )) {
                Picker("", selection: $durationMinutes) {
                    ForEach([20, 30, 45, 60, 75], id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(ink)
            }

            Divider()

            settingsRow(title: ATHLTHLocalization.choose(
                english: "Muscle focus", norwegian: "Muskelgrupper"
            )) {
                Menu {
                    Button {
                        focusBodyParts = []
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Let AI decide",
                                norwegian: "La AI bestemme"
                            ),
                            systemImage: focusBodyParts.isEmpty
                                ? "checkmark.circle.fill" : "sparkles"
                        )
                    }
                    Divider()
                    ForEach(availableBodyParts, id: \.self) { part in
                        Button {
                            if focusBodyParts.contains(part) {
                                focusBodyParts.remove(part)
                            } else {
                                focusBodyParts.insert(part)
                            }
                        } label: {
                            Label(
                                exerciseLibrary.localizedBodyPartTitle(part),
                                systemImage: focusBodyParts.contains(part)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(
                            focusBodyParts.isEmpty
                                ? ATHLTHLocalization.choose(
                                    english: "AI decides",
                                    norwegian: "AI bestemmer"
                                )
                                : focusBodyParts.sorted().map {
                                    exerciseLibrary.localizedBodyPartTitle($0)
                                }.joined(separator: " + ")
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(ink)
                }
            }

            Divider()

            settingsRow(title: ATHLTHLocalization.choose(
                english: "Equipment", norwegian: "Utstyr"
            )) {
                Menu {
                    Button(ATHLTHLocalization.choose(
                        english: "Any equipment", norwegian: "Alt utstyr"
                    )) { equipmentFilter = nil }

                    Divider()

                    ForEach(availableEquipment, id: \.self) { equipment in
                        Button(exerciseLibrary.localizedEquipmentTitle(equipment)) {
                            equipmentFilter = equipment
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(equipmentFilter.map {
                            exerciseLibrary.localizedEquipmentTitle($0)
                        } ?? ATHLTHLocalization.choose(
                            english: "Any equipment", norwegian: "Alt utstyr"
                        ))
                        .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(ink)
                }
            }

            Divider()

            Stepper(value: $exerciseCount, in: 1...8) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Exercises", norwegian: "Antall øvelser"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(exerciseCount)")
                        .monospacedDigit()
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                }
            }
            .tint(ink)

            Divider()

            Toggle(isOn: $personalize) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Consider training history",
                        norwegian: "Ta hensyn til treningshistorikk"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)

                    Text(ATHLTHLocalization.choose(
                        english: "Use recently trained exercises and muscle groups to vary the selection.",
                        norwegian: "Bruk tidligere øvelser og muskelgrupper for å unngå unødvendig gjentakelse."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(ink)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: hasEnoughExercises
                      ? "checkmark.seal" : "exclamationmark.circle")
                    .foregroundStyle(hasEnoughExercises ? accent : Color.orange)
                Text(hasEnoughExercises
                     ? ATHLTHLocalization.choose(
                        english: "\(candidateEntries.count) compatible library exercises available.",
                        norwegian: "\(candidateEntries.count) passende øvelser tilgjengelig i biblioteket."
                     )
                     : ATHLTHLocalization.choose(
                        english: "Found \(candidateEntries.count) matching exercises, but you requested \(exerciseCount). Reduce the count, change the focus/equipment or add exercises.",
                        norwegian: "Fant \(candidateEntries.count) passende øvelser, men du har valgt \(exerciseCount). Reduser antallet, endre fokus/utstyr eller legg til øvelser."
                     ))
                    .font(.caption)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(canvas, in: RoundedRectangle(cornerRadius: 13))

            if !existingExercises.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "The suggestion adds to your existing exercises; it does not replace them.",
                    norwegian: "Forslaget supplerer øvelsene som allerede ligger i økten."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(separator))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            if let plan {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "YOUR WORKOUT", norwegian: "DITT ØKTFORSLAG"
                            ))
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(accent)

                            Text(plan.title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "checkmark.shield")
                            .font(.title3)
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                    }

                    HStack(spacing: 8) {
                        Label(
                            "\(resolvedSuggestions.count) " +
                                ATHLTHLocalization.choose(
                                    english: "exercises", norwegian: "øvelser"
                                ),
                            systemImage: "dumbbell"
                        )
                        Text("·")
                        Label("Ca. \(plan.estimatedMinutes) min", systemImage: "clock")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    Label(
                        sourceFilter.title,
                        systemImage: "books.vertical"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)

                    if !plan.summary.isEmpty {
                        Text(plan.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().overlay(separator)

                if resolvedSuggestions.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No exercises remain",
                            norwegian: "Ingen øvelser igjen"
                        ),
                        systemImage: "dumbbell",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Adjust your choices or generate a new suggestion.",
                            norwegian: "Juster valgene eller generer et nytt forslag."
                        ))
                    )
                } else {
                    ForEach(
                        Array(resolvedSuggestions.enumerated()),
                        id: \.offset
                    ) { index, pair in
                        let suggestion = pair.0
                        let entry = pair.1

                        HStack(alignment: .top, spacing: 12) {
                            ATHLTHAIExerciseSuggestionImage(entry: entry)
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ink)
                                        .frame(width: 24, height: 24)
                                        .background(.regularMaterial, in: Circle())
                                        .padding(3)
                                }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(exerciseLibrary.localizedExerciseName(entry))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(
                                    "\(suggestion.sets) × \(suggestion.reps) · " +
                                        "\(suggestion.restSeconds) s " +
                                        ATHLTHLocalization.choose(
                                            english: "rest", norwegian: "pause"
                                        )
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                if !suggestion.reason.isEmpty {
                                    Text(suggestion.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                HStack(spacing: 13) {
                                    Button {
                                        replacingSuggestion = suggestion
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Replace", norwegian: "Bytt"
                                            ),
                                            systemImage: "arrow.triangle.2.circlepath"
                                        )
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(accent)

                                    Menu {
                                        Button {
                                            inspectingEntry = entry
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "View exercise", norwegian: "Se øvelse"
                                                ),
                                                systemImage: "info.circle"
                                            )
                                        }

                                        if index > 0 {
                                            Button {
                                                move(suggestion.exerciseID, by: -1)
                                            } label: {
                                                Label(
                                                    ATHLTHLocalization.choose(
                                                        english: "Move up", norwegian: "Flytt opp"
                                                    ),
                                                    systemImage: "arrow.up"
                                                )
                                            }
                                        }
                                        if index + 1 < resolvedSuggestions.count {
                                            Button {
                                                move(suggestion.exerciseID, by: 1)
                                            } label: {
                                                Label(
                                                    ATHLTHLocalization.choose(
                                                        english: "Move down", norwegian: "Flytt ned"
                                                    ),
                                                    systemImage: "arrow.down"
                                                )
                                            }
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            remove(suggestion.exerciseID)
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Remove", norwegian: "Fjern"
                                                ),
                                                systemImage: "trash"
                                            )
                                        }
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "More", norwegian: "Flere valg"
                                            ),
                                            systemImage: "ellipsis.circle"
                                        )
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .frame(minHeight: 32, alignment: .leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)

                        if index < resolvedSuggestions.count - 1 {
                            Divider().overlay(separator)
                        }
                    }
                }

                Button {
                    applyPlan()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Add all to workout",
                            norwegian: "Legg til i økten"
                        ),
                        systemImage: "plus.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 53)
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .disabled(
                    isGenerating || resolvedSuggestions.isEmpty ||
                    resolvedSuggestions.count != editedSuggestions.count
                )
                .accessibilityIdentifier("athlth-ai-apply-library-exercises")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(separator))
    }

    private var singleSuggestionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let match = resolvedSuggestions.first {
                let suggestion = match.0
                let entry = match.1
                HStack(alignment: .top, spacing: 12) {
                    ATHLTHAIExerciseSuggestionImage(entry: entry)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name)
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .lineLimit(2)
                        Text("\(suggestion.sets) sett · \(suggestion.reps) reps · \(suggestion.restSeconds)s pause")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        if let group = entry.bodyPart, !group.isEmpty {
                            Text(group)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                }
                if !suggestion.reason.isEmpty {
                    Text(suggestion.reason)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    applyPlan()
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Add this exercise",
                        norwegian: "Legg til denne øvelsen"
                    ), systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        ATHLTHTheme.accentDeep,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                Button {
                    generate()
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Suggest another exercise",
                        norwegian: "Foreslå en annen øvelse"
                    ), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accentDeep)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "No compatible exercise was suggested. Try another.",
                    norwegian: "Ingen passende øvelse ble foreslått. Prøv igjen."
                ))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                generateButton
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ATHLTHPlanDesign.warmSurface,
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private var generateButton: some View {
        VStack(spacing: 12) {
            Button {
                generate()
            } label: {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(
                        plan == nil
                            ? ATHLTHLocalization.choose(
                                english: "Build my workout", norwegian: "Bygg øktforslag"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Generate another", norwegian: "Lag et nytt forslag"
                            )
                    )
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    ink,
                    in: RoundedRectangle(cornerRadius: 15)
                )
            }
            .buttonStyle(.plain)
            .disabled(isGenerating || !hasEnoughExercises)
            .opacity(isGenerating ? 0.72 : 1)
            .accessibilityIdentifier("athlth-ai-build-from-library")

            if plan != nil && !quickSuggestion {
                Button {
                    editedSuggestions = []
                    plan = nil
                    errorMessage = nil
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Adjust criteria", norwegian: "Juster kriterier"
                        ),
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(ink)
            }
        }
    }

    private func settingsRow<Content: View>(
        title: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )

            Spacer()

            content()
        }
    }

    private func generate() {
        guard !isGenerating else {
            return
        }

        // A request for "another" suggestion should exclude the last
        // recommendation whenever at least one other library candidate exists.
        let previousSuggestionIDs = quickSuggestion
            ? Set(resolvedSuggestions.map { $0.0.exerciseID })
            : Set<UUID>()
        let alternateEntries = candidateEntries.filter {
            !previousSuggestionIDs.contains($0.id)
        }
        let requestedEntries = alternateEntries.isEmpty
            ? candidateEntries : alternateEntries
        let candidates =
            requestedEntries
                .map {
                    entry in

                    StrengthAIExerciseCandidate(
                        exerciseID:
                            entry.id,
                        name:
                            entry
                                .canonicalName,
                        bodyPart:
                            entry.bodyPart,
                        primaryMuscles:
                            entry
                                .exercise
                                .primaryMuscles,
                        secondaryMuscles:
                            entry
                                .exercise
                                .secondaryMuscles,
                        equipment:
                            entry
                                .exercise
                                .equipment,
                        category:
                            entry.category,
                        difficulty:
                            entry.difficulty
                    )
                }

        let requiredCount = quickSuggestion ? 1 : exerciseCount
        guard candidates.count >= requiredCount else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Found \(candidates.count) eligible library exercises, but you requested \(requiredCount). Adjust the count, source, focus or equipment.",
                norwegian: "Fant \(candidates.count) passende øvelser i biblioteket, men du ønsker \(requiredCount). Endre antall, kilde, fokus eller utstyr."
            )
            return
        }
        let allowedIDs = Set(candidates.map(\.exerciseID))

        let request =
            StrengthAIExerciseRequest(
                goal: goal.rawValue,
                durationMinutes:
                    durationMinutes,
                exerciseCount: requiredCount,
                focusBodyPart:
                    focusBodyParts.count == 1 ? focusBodyParts.first : nil,
                focusBodyParts: focusBodyParts.isEmpty
                    ? nil : focusBodyParts.sorted(),
                personalize:
                    personalize,
                language:
                    ATHLTHLocalization
                        .isNorwegian
                        ? "nb"
                        : "en",
                existingExerciseIDs:
                    existingExercises
                        .compactMap(
                            \.exerciseID
                        ),
                existingExerciseNames:
                    existingExercises
                        .map {
                            $0.embeddedExercise
                                .name
                        },
                recentWorkouts:
                    personalize
                        ? recentContext
                        : [],
                candidates:
                    candidates
            )

        isGenerating = true
        errorMessage = nil

        Task {
            defer {
                isGenerating = false
            }

            do {
                let generated =
                    try await service
                        .generate(
                            request
                        )

                guard StrengthAIExerciseSelectionPolicy.verified(
                    generated.exercises,
                    allowedIDs: allowedIDs,
                    existingIDs: existingIDs,
                    requiredCount: requiredCount
                ) else {
                    throw StrengthAIExercisePlannerError.invalidResult
                }

                editedSuggestions = generated.exercises
                plan = generated
            } catch {
                errorMessage =
                    resolvedErrorMessage(
                        error
                    )
            }
        }
    }

    private var recentContext:
        [StrengthAIRecentWorkout] {
        let calendar =
            Calendar.current

        return recentWorkouts
            .filter {
                $0.endedAt != nil
            }
            .prefix(4)
            .map {
                workout in

                let daysAgo =
                    max(
                        calendar.dateComponents(
                            [.day],
                            from:
                                workout
                                    .startedAt,
                            to: Date()
                        ).day ?? 0,
                        0
                    )

                let exercises =
                    workout.exercises
                        .prefix(10)
                        .map {
                            exercise in

                            StrengthAIRecentExercise(
                                name:
                                    exercise
                                        .exercise
                                        .name,
                                primaryMuscles:
                                    exercise
                                        .exercise
                                        .primaryMuscles,
                                completedSets:
                                    exercise
                                        .sets
                                        .filter(
                                            \.isCompleted
                                        )
                                        .count
                            )
                        }

                return StrengthAIRecentWorkout(
                    title:
                        workout.title,
                    daysAgo:
                        daysAgo,
                    exercises:
                        exercises
                )
            }
    }

    private func applyPlan() {
        // Revalidate at the last possible moment, including after the user
        // replaces or removes rows or the account-local library changes.
        let allowedIDs = Set(candidateEntries.map(\.id))
        guard StrengthAIExerciseSelectionPolicy.verified(
            editedSuggestions,
            allowedIDs: allowedIDs,
            existingIDs: existingIDs,
            requiredCount: editedSuggestions.count
        ), resolvedSuggestions.count == editedSuggestions.count else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Some exercises are no longer in the selected library. Review the suggestion again.",
                norwegian: "En eller flere øvelser finnes ikke lenger i det valgte biblioteket. Se over forslaget på nytt."
            )
            return
        }
        let additions =
            resolvedSuggestions
                .map {
                    suggestion,
                    entry in

                    PlannedExercise(
                        id: UUID(),
                        exerciseID:
                            entry.id,
                        embeddedExercise:
                            entry
                                .exercise
                                .snapshot,
                        sets:
                            min(
                                max(
                                    suggestion
                                        .sets,
                                    1
                                ),
                                8
                            ),
                        reps:
                            min(
                                max(
                                    suggestion
                                        .reps,
                                    1
                                ),
                                50
                            ),
                        targetWeightKilograms:
                            nil,
                        targetRPE:
                            suggestion
                                .targetRPE
                                .map {
                                    min(
                                        max(
                                            $0,
                                            1
                                        ),
                                        10
                                    )
                                },
                        restSeconds:
                            min(
                                max(
                                    suggestion
                                        .restSeconds,
                                    15
                                ),
                                600
                            ),
                        notes:
                            suggestion
                                .reason
                                .isEmpty
                                ? nil
                                : suggestion
                                    .reason,
                        targetRIR: nil,
                        supersetGroupID:
                            nil,
                        progression:
                            StrengthProgressionRule
                                .none
                    )
                }

        guard !additions
            .isEmpty
        else {
            return
        }

        onApply(additions)
        dismiss()
    }

    private func replace(_ id: UUID, with entry: ExerciseLibraryEntry) {
        // The picker is read-only, but validate again if library contents
        // changed while it was open.
        guard availableReplacements.contains(where: { $0.id == entry.id }),
              let index = editedSuggestions.firstIndex(where: {
                  $0.exerciseID == id
              }) else { return }
        let current = editedSuggestions[index]
        editedSuggestions[index] = StrengthAIExerciseSuggestion(
            exerciseID: entry.id,
            sets: current.sets,
            reps: current.reps,
            restSeconds: current.restSeconds,
            targetRPE: current.targetRPE,
            reason: ""
        )
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = editedSuggestions.firstIndex(where: {
            $0.exerciseID == id
        }) else { return }
        let destination = index + offset
        guard editedSuggestions.indices.contains(destination) else { return }
        editedSuggestions.swapAt(index, destination)
    }

    private func remove(_ id: UUID) {
        editedSuggestions.removeAll { $0.exerciseID == id }
    }

    private func resolvedErrorMessage(
        _ error: Error
    ) -> String {
        // Supabase's generic localizedDescription hides the actual HTTP
        // status and JSON error code. Surface actionable, localized errors
        // without leaking server internals or the user's private context.
        if case let FunctionsError.httpError(status, data) = error {
            let serverError = try? JSONDecoder().decode(
                StrengthAIServiceErrorPayload.self,
                from: data
            )

            if serverError?.code == "PREMIUM_REQUIRED" || status == 403 {
                return ATHLTHLocalization.choose(
                    english: "AI exercise selection requires ATHLTH+.",
                    norwegian: "AI-valg av øvelser krever ATHLTH+."
                )
            }
            if serverError?.code == "AI_RATE_LIMIT" || status == 429 {
                return ATHLTHLocalization.choose(
                    english: "AI request limit reached. Try again a little later.",
                    norwegian: "Grensen for AI-forespørsler er nådd. Prøv igjen litt senere."
                )
            }

            switch status {
            case 401:
                return ATHLTHLocalization.choose(
                    english: "Your session has expired. Sign in again and retry.",
                    norwegian: "Innloggingen er utløpt. Logg inn på nytt og prøv igjen."
                )
            case 400:
                return ATHLTHLocalization.choose(
                    english: "The selected exercises could not be used. Try another focus or fewer exercises.",
                    norwegian: "Valgte øvelser kunne ikke brukes. Prøv et annet fokus eller færre øvelser."
                )
            case 502, 503, 504:
                return ATHLTHLocalization.choose(
                    english: "The ATHLTH AI service is temporarily unavailable. Try again shortly.",
                    norwegian: "ATHLTH AI-tjenesten er midlertidig utilgjengelig. Prøv igjen om litt."
                )
            default:
                return ATHLTHLocalization.choose(
                    english: "The AI request failed (HTTP \\(status)). Try again.",
                    norwegian: "AI-forespørselen feilet (HTTP \\(status)). Prøv igjen."
                )
            }
        }

        if error is URLError {
            return ATHLTHLocalization.choose(
                english: "Check your internet connection and try again.",
                norwegian: "Kontroller internettforbindelsen og prøv igjen."
            )
        }

        return ATHLTHLocalization.choose(
            english: "ATHLTH AI could not create a suggestion right now. Try again.",
            norwegian: "ATHLTH AI klarte ikke å lage et forslag akkurat nå. Prøv igjen."
        )
    }

    private func errorCard(
        _ message: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )
            .foregroundStyle(
                Color.orange
            )

            Text(message)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

            Spacer(
                minLength: 0
            )
        }
        .padding(13)
        .background(
            Color.orange
                .opacity(0.08),
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
    }
}


private struct ATHLTHAIExerciseSuggestionImage: View {
    let entry: ExerciseLibraryEntry

    var body: some View {
        ZStack {
            ATHLTHPlanDesign.warmSurface

            if let url = entry.exercise.imageURL {
                if url.isFileURL, let picture = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                } else {
                    ATHLTHStorageImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(entry.name)
    }

    private var placeholder: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.title2)
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
    }
}

private enum StrengthAIExercisePlannerError:
    LocalizedError
{
    case emptyResult
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .emptyResult:
            return "ATHLTH AI returned no exercises."
        case .invalidResult:
            return "ATHLTH AI returned an exercise outside the allowed library selection."
        }
    }
}
