import SwiftUI

/// The running-session picker uses the same canonical exercise directory
/// as the Exercises tab. Personal saved main sections, old presets and
/// published running workout mains cannot diverge into duplicate pickers.
struct ATHLTHRunningExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let userID: UUID
    let phase: WorkoutPhaseKind
    let onSelect: ([WorkoutTemplateBlock]) -> Void

    var body: some View {
        ATHLTHCompoundExerciseLibraryView(
            runningOnly: true, insertionPhase: phase,
            onSelect: { blocks in
                onSelect(ATHLTHIntervalRecipeEditing.forEditing(blocks))
                dismiss()
            }
        )
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Add running exercise", norwegian: "Legg til løpeøvelse"
        ))
    }
}
