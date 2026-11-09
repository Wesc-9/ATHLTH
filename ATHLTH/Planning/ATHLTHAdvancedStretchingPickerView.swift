import SwiftUI

/// Retains the existing "Stretching" entry in the advanced plan builder.
/// Its destination now shares the full recovery/wellness exercise library.
struct ATHLTHAdvancedStretchingPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let phase: WorkoutPhaseKind
    let onAdd: ([WorkoutTemplateBlock]) -> Void

    var body: some View {
        NavigationStack {
            ATHLTHRecoveryWellnessLibraryView(
                onAdd: { guide in
                    let block = ATHLTHWellnessBlockFactory.block(
                        for: guide, phase: phase
                    )
                    onAdd([block])
                    dismiss()
                },
                onClose: { dismiss() }
            )
        }
    }
}
