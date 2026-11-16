import SwiftUI

/// Reuses the library's full exercise card for workout and training-plan
/// timelines. A private exercise from another athlete remains a portable
/// preview until the recipient explicitly imports their own private copy.
struct ATHLTHLinkedExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    let block: WorkoutTemplateBlock
    var sharedByUsername: String? = nil
    var originalCreatorID: UUID? = nil
    var originalCreatorUsername: String? = nil
    var originalExerciseID: UUID? = nil

    @State private var imported = false

    private var matched: ExerciseLibraryEntry? {
        if originalCreatorID != nil || originalExerciseID != nil {
            // Received exercises are identified by immutable origin UUID,
            // never by a matching title. Several distinct personal exercises
            // are intentionally allowed to have the same visible name.
            guard let sourceID = originalExerciseID ?? block.exerciseID else {
                return nil
            }
            return library.customExercises.first {
                $0.exercise.sharedSourceExerciseID == sourceID
            }
        }
        return ATHLTHExerciseReferenceResolver.resolve(
            block, in: library.allExercises
        )
    }

    private var previewSnapshot: ExerciseSnapshot {
        let source = block.exerciseSnapshot ?? ExerciseSnapshot(
            name: block.title, instructions: [],
            primaryMuscles: [], secondaryMuscles: [],
            equipment: [], imageURL: nil
        )
        return ATHLTHExerciseReferenceResolver.safeImportedSnapshot(
            source, fallbackTitle: block.title
        ) ?? ExerciseSnapshot(
            name: block.title, instructions: [],
            primaryMuscles: [], secondaryMuscles: [],
            equipment: [], imageURL: nil
        )
    }

    private var displayEntry: ExerciseLibraryEntry {
        if let matched { return matched }
        let details = previewSnapshot
        var exercise = Exercise(
            id: block.exerciseID ?? UUID(),
            origin: .publicCatalog,
            ownerID: nil,
            name: details.name,
            instructions: details.instructions,
            primaryMuscles: details.primaryMuscles,
            secondaryMuscles: details.secondaryMuscles ?? [],
            equipment: details.equipment,
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        exercise.sharedByUsername = sharedByUsername
        exercise.originalCreatorID = originalCreatorID
        exercise.originalCreatorUsername = originalCreatorUsername
        exercise.originalExerciseID = originalExerciseID
        return ExerciseLibraryEntry(
            id: exercise.id,
            exercise: exercise,
            source: .athlthCatalog,
            sourceIdentifier: nil,
            summary: nil, tips: [],
            category: "custom", difficulty: nil,
            bodyPart: details.primaryMuscles.first,
            imageStartURL: nil, imagePeakURL: nil
        )
    }

    private var plannedTargets: [(label: String, value: String)] {
        var result: [(label: String, value: String)] = []
        if let sets = block.setCount, sets > 0 {
            result.append((
                ATHLTHLocalization.choose(english: "Sets", norwegian: "Sett"),
                "\(sets)"
            ))
        }
        if let repetitions = block.repetitions, repetitions > 0 {
            let value = block.targetRepetitionsMaximum.map { maximum in
                maximum > repetitions
                    ? "\(repetitions)–\(maximum)" : "\(repetitions)"
            } ?? "\(repetitions)"
            result.append((
                ATHLTHLocalization.choose(english: "Reps", norwegian: "Reps"),
                value
            ))
        }
        if let rest = block.restBetweenSetsSeconds, rest > 0 {
            result.append((
                ATHLTHLocalization.choose(english: "Set rest", norwegian: "Settpause"),
                ATHLTHWorkoutStepCopy.duration(rest)
            ))
        }
        if let rir = block.targetRepsInReserve {
            result.append(("RIR", "\(rir)"))
        }
        if let weight = block.targetWeightKilograms, weight > 0 {
            result.append((
                ATHLTHLocalization.choose(english: "Target weight", norwegian: "Målvekt"),
                "\(weight.formatted()) kg"
            ))
        }
        return result
    }

    private var workoutTargetsStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(ATHLTHLocalization.choose(
                    english: "Targets in this workout",
                    norwegian: "Mål i denne treningsøkten"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(plannedTargets.enumerated()), id: \.offset) { _, target in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.label.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            Text(target.value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                        }
                        .padding(.horizontal, 12)
                        .frame(minWidth: 85, minHeight: 56, alignment: .leading)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            ATHLTHPlanDesign.warmSurface,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .padding(.horizontal, 15)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !plannedTargets.isEmpty {
                    workoutTargetsStrip
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
                if matched == nil {
                    HStack(spacing: 9) {
                        Image(systemName: "person.crop.square")
                        Text(block.exerciseSnapshot != nil
                             ? ATHLTHLocalization.choose(
                                english: "Exercise information shared by the plan creator",
                                norwegian: "Øvelsesinformasjon delt av den som laget planen")
                             : ATHLTHLocalization.choose(
                                english: "Not found in your exercise library. Details can be completed in My Exercises.",
                                norwegian: "Finnes ikke i øvelsesbiblioteket. Du kan fylle inn detaljer i Mine øvelser."))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .padding(12)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 15)
                }

                ExerciseDetailView(
                    entry: displayEntry,
                    selectionTitle: nil,
                    onSelect: nil
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if matched == nil {
                    VStack(spacing: 7) {
                        Button {
                            let result = library.importSharedExercise(
                                previewSnapshot,
                                ownerID: session.profile.userID,
                                sourceExerciseID: originalExerciseID ?? block.exerciseID,
                                sharedByUsername: sharedByUsername,
                                originalCreatorID: originalCreatorID,
                                originalCreatorUsername: originalCreatorUsername,
                                originalExerciseID: originalExerciseID
                            )
                            if result != nil {
                                imported = true
                            }
                        } label: {
                            Label(
                                imported
                                    ? ATHLTHLocalization.choose(
                                        english: "In My Exercises",
                                        norwegian: "I Mine øvelser")
                                    : ATHLTHLocalization.choose(
                                        english: "Add to My Exercises",
                                        norwegian: "Legg til i Mine øvelser"),
                                systemImage: imported
                                    ? "checkmark.circle.fill"
                                    : "square.and.arrow.down"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(imported)

                        if block.exerciseSnapshot == nil {
                            Text(ATHLTHLocalization.choose(
                                english: "Only the exercise name was supplied. Review the technique before training.",
                                norwegian: "Kun øvelsesnavnet fulgte med. Kontroller teknikken før du trener."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) { dismiss() }
                }
            }
        }
    }
}
