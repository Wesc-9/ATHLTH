import SwiftUI
import Supabase

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
    let onApply: ([PlannedExercise]) -> Void

    @State private var goal:
        StrengthAIWorkoutGoal = .general
    @State private var durationMinutes = 45
    @State private var exerciseCount = 5
    @State private var focusBodyPart: String?
    @State private var personalize = true
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var plan:
        StrengthAIExercisePlan?

    private let service =
        StrengthAIExerciseService()

    private var availableBodyParts: [String] {
        exerciseLibrary.bodyParts
    }

    private var candidateEntries:
        [ExerciseLibraryEntry] {
        let existingIDs =
            Set(
                existingExercises
                    .compactMap(\.exerciseID)
            )

        let filtered =
            exerciseLibrary.allExercises
                .filter {
                    !existingIDs.contains($0.id) &&
                    $0.exercise
                        .snapshot
                        .defaultStrengthTargetKind ==
                        .reps
                }

        let sorted =
            filtered.sorted {
                lhs,
                rhs in

                let lhsFocus =
                    focusScore(lhs)
                let rhsFocus =
                    focusScore(rhs)

                if lhsFocus != rhsFocus {
                    return lhsFocus > rhsFocus
                }

                if lhs.source != rhs.source {
                    return lhs.source ==
                        .athlthCatalog
                }

                return lhs.canonicalName
                    .localizedCaseInsensitiveCompare(
                        rhs.canonicalName
                    ) ==
                    .orderedAscending
            }

        return Array(
            sorted.prefix(80)
        )
    }

    private var resolvedSuggestions:
        [(StrengthAIExerciseSuggestion,
          ExerciseLibraryEntry)] {
        guard let plan else {
            return []
        }

        let byID =
            Dictionary(
                uniqueKeysWithValues:
                    exerciseLibrary
                        .allExercises
                        .map {
                            ($0.id, $0)
                        }
            )

        var seen:
            Set<UUID> = []

        return plan.exercises
            .compactMap {
                suggestion in

                guard
                    !seen.contains(
                        suggestion
                            .exerciseID
                    ),
                    let entry =
                        byID[
                            suggestion
                                .exerciseID
                        ]
                else {
                    return nil
                }

                seen.insert(
                    suggestion
                        .exerciseID
                )

                return (
                    suggestion,
                    entry
                )
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    introCard
                    setupCard

                    if let errorMessage {
                        errorCard(
                            errorMessage
                        )
                    }

                    if plan != nil {
                        resultCard
                    }

                    generateButton
                }
                .padding(16)
                .padding(.bottom, 26)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.20)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "AI exercise picker",
                    norwegian:
                        "AI velger øvelser"
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
            [.large]
        )
    }

    private var introCard: some View {
        ATHLTHCard {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                Image(
                    systemName:
                        "sparkles"
                )
                .font(
                    .title2.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.12),
                    in: Circle()
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Let ATHLTH build this session",
                            norwegian:
                                "La ATHLTH bygge økten"
                        )
                    )
                    .font(
                        .headline.weight(
                            .bold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "AI only chooses exercises that already exist in your ATHLTH library. You review everything before it is added.",
                            norwegian:
                                "AI velger kun øvelser som allerede finnes i ATHLTH-biblioteket. Du ser gjennom alt før det legges til."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
        }
    }

    private var setupCard: some View {
        ATHLTHCard {
            VStack(spacing: 14) {
                settingsRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Goal",
                            norwegian: "Mål"
                        )
                ) {
                    Picker(
                        "",
                        selection: $goal
                    ) {
                        ForEach(
                            StrengthAIWorkoutGoal
                                .allCases
                        ) {
                            option in

                            Text(
                                option.title
                            )
                            .tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Divider()

                settingsRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Time",
                            norwegian: "Tid"
                        )
                ) {
                    Picker(
                        "",
                        selection:
                            $durationMinutes
                    ) {
                        ForEach(
                            [20, 30, 45, 60, 75],
                            id: \.self
                        ) {
                            value in

                            Text(
                                "\(value) min"
                            )
                            .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Divider()

                settingsRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Focus",
                            norwegian: "Fokus"
                        )
                ) {
                    Menu {
                        Button(
                            ATHLTHLocalization.choose(
                                english:
                                    "Automatic",
                                norwegian:
                                    "Automatisk"
                            )
                        ) {
                            focusBodyPart =
                                nil
                        }

                        Divider()

                        ForEach(
                            availableBodyParts,
                            id: \.self
                        ) {
                            part in

                            Button(
                                exerciseLibrary
                                    .localizedBodyPartTitle(
                                        part
                                    )
                            ) {
                                focusBodyPart =
                                    part
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(
                                focusBodyPart
                                    .map {
                                        exerciseLibrary
                                            .localizedBodyPartTitle(
                                                $0
                                            )
                                    } ??
                                ATHLTHLocalization.choose(
                                    english:
                                        "Automatic",
                                    norwegian:
                                        "Automatisk"
                                )
                            )

                            Image(
                                systemName:
                                    "chevron.up.chevron.down"
                            )
                            .font(.caption2)
                        }
                    }
                }

                Divider()

                Stepper(
                    value: $exerciseCount,
                    in: 3...8
                ) {
                    HStack {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Exercises",
                                norwegian:
                                    "Øvelser"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )

                        Spacer()

                        Text(
                            "\(exerciseCount)"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                Divider()

                Toggle(
                    isOn: $personalize
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Use ATHLTH history",
                                norwegian:
                                    "Bruk ATHLTH-historikk"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Uses your recent strength exercise and muscle-group history to reduce unnecessary repetition.",
                                norwegian:
                                    "Bruker nylige styrkeøvelser og muskelgrupper for å unngå unødvendig gjentakelse."
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                if !existingExercises
                    .isEmpty {
                    Divider()

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "AI will complement the exercises you already selected, not replace them.",
                            norwegian:
                                "AI supplerer øvelsene du allerede har valgt, og erstatter dem ikke."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                    .frame(
                        maxWidth:
                            .infinity,
                        alignment: .leading
                    )
                }
            }
        }
    }

    private var resultCard: some View {
        ATHLTHCard {
            if let plan {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    HStack(
                        alignment: .top
                    ) {
                        VStack(
                            alignment:
                                .leading,
                            spacing: 3
                        ) {
                            Text(plan.title)
                                .font(
                                    .headline
                                        .weight(
                                            .bold
                                        )
                                )

                            Text(
                                ATHLTHLocalization.format(
                                    english:
                                        "About %d min",
                                    norwegian:
                                        "Ca. %d min",
                                    plan
                                        .estimatedMinutes
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()

                        Image(
                            systemName:
                                "sparkles"
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
                    }

                    if !plan.summary
                        .isEmpty {
                        Text(plan.summary)
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                    }

                    Divider()

                    ForEach(
                        Array(
                            resolvedSuggestions
                                .enumerated()
                        ),
                        id: \.offset
                    ) {
                        index,
                        resolved in

                        let suggestion =
                            resolved.0
                        let entry =
                            resolved.1

                        HStack(
                            alignment: .top,
                            spacing: 11
                        ) {
                            Text(
                                "\(index + 1)"
                            )
                            .font(
                                .caption.bold()
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accent
                            )
                            .frame(
                                width: 27,
                                height: 27
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Circle()
                            )

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 3
                            ) {
                                Text(
                                    entry.name
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )

                                Text(
                                    "\(suggestion.sets) × \(suggestion.reps) · \(suggestion.restSeconds) s"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )

                                if !suggestion
                                    .reason
                                    .isEmpty {
                                    Text(
                                        suggestion
                                            .reason
                                    )
                                    .font(
                                        .caption2
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }
                            }

                            Spacer()
                        }
                    }

                    Button {
                        applyPlan()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Add to workout",
                                norwegian:
                                    "Legg til i økten"
                            ),
                            systemImage:
                                "plus.circle.fill"
                        )
                        .font(
                            .headline
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(height: 46)
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .tint(
                        ATHLTHTheme.vitality
                    )
                    .disabled(
                        resolvedSuggestions
                            .isEmpty
                    )
                }
            }
        }
    }

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            HStack(spacing: 9) {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(
                        systemName:
                            "sparkles"
                    )
                }

                Text(
                    plan == nil
                        ? ATHLTHLocalization.choose(
                            english:
                                "Generate exercises",
                            norwegian:
                                "Foreslå øvelser"
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Generate another",
                            norwegian:
                                "Lag et nytt forslag"
                        )
                )
            }
            .font(
                .headline.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                .white
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 50)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .accentDeep,
                        ATHLTHTheme
                            .vitality
                    ],
                    startPoint:
                        .leading,
                    endPoint:
                        .trailing
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 16,
                        style:
                            .continuous
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(
            isGenerating ||
            candidateEntries
                .count <
                min(
                    exerciseCount,
                    3
                )
        )
        .opacity(
            isGenerating
                ? 0.76
                : 1
        )
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

    private func focusScore(
        _ entry:
            ExerciseLibraryEntry
    ) -> Int {
        guard let focusBodyPart else {
            return entry.source ==
                .athlthCatalog
                ? 2
                : 0
        }

        let target =
            focusBodyPart
                .lowercased()

        if entry.bodyPart?
            .lowercased() ==
            target {
            return 10
        }

        let muscles =
            entry.exercise
                .primaryMuscles +
            entry.exercise
                .secondaryMuscles

        if muscles.contains(
            where: {
                $0.lowercased()
                    .contains(
                        target
                    ) ||
                target.contains(
                    $0.lowercased()
                )
            }
        ) {
            return 8
        }

        return entry.source ==
            .athlthCatalog
            ? 1
            : 0
    }

    private func generate() {
        guard !isGenerating else {
            return
        }

        let candidates =
            candidateEntries
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

        guard !candidates.isEmpty else {
            errorMessage =
                ATHLTHLocalization.choose(
                    english:
                        "No compatible strength exercises are available yet.",
                    norwegian:
                        "Ingen kompatible styrkeøvelser er tilgjengelige ennå."
                )
            return
        }

        let request =
            StrengthAIExerciseRequest(
                goal: goal.rawValue,
                durationMinutes:
                    durationMinutes,
                exerciseCount:
                    min(
                        exerciseCount,
                        candidates.count
                    ),
                focusBodyPart:
                    focusBodyPart,
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

                guard !generated
                    .exercises
                    .isEmpty
                else {
                    throw StrengthAIExercisePlannerError
                        .emptyResult
                }

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

    private func resolvedErrorMessage(
        _ error: Error
    ) -> String {
        let raw =
            error.localizedDescription
                .lowercased()

        if raw.contains(
            "premium"
        ) ||
            raw.contains(
                "athlth+"
            ) {
            return ATHLTHLocalization.choose(
                english:
                    "AI exercise selection requires ATHLTH+.",
                norwegian:
                    "AI-valg av øvelser krever ATHLTH+."
            )
        }

        if raw.contains(
            "rate"
        ) ||
            raw.contains(
                "limit"
            ) {
            return ATHLTHLocalization.choose(
                english:
                    "AI has reached its temporary request limit. Try again a little later.",
                norwegian:
                    "AI har nådd en midlertidig forespørselsgrense. Prøv igjen litt senere."
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "ATHLTH AI could not create a suggestion right now. Try again.",
            norwegian:
                "ATHLTH AI klarte ikke å lage et forslag akkurat nå. Prøv igjen."
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

private enum StrengthAIExercisePlannerError:
    LocalizedError
{
    case emptyResult

    var errorDescription: String? {
        "ATHLTH AI returned no valid exercises."
    }
}
