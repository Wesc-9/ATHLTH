import SwiftUI

/// Reuses the library's full exercise card for workout and training-plan
/// timelines. A private exercise from another athlete remains a portable
/// preview until the recipient explicitly imports their own private copy.
struct ATHLTHLinkedExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    let block: WorkoutTemplateBlock

    @State private var imported = false

    private var matched: ExerciseLibraryEntry? {
        ATHLTHExerciseReferenceResolver.resolve(block, in: library.allExercises)
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
        let exercise = Exercise(
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                                previewSnapshot, ownerID: session.profile.userID
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
