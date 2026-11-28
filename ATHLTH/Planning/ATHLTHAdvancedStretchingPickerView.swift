import SwiftUI

/// Retains the existing "Stretching" entry in the advanced plan builder.
/// Its destination now shares the full recovery/wellness exercise library.
struct ATHLTHAdvancedStretchingPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let phase: WorkoutPhaseKind
    var onClose: (() -> Void)? = nil
    @State private var didFinish = false
    let onAdd: ([WorkoutTemplateBlock]) -> Void

    var body: some View {
        NavigationStack {
            ATHLTHRecoveryWellnessLibraryView(
                onAdd: { guide in
                    let block = ATHLTHWellnessBlockFactory.block(
                        for: guide, phase: phase
                    )
                    guard !didFinish else { return }
                    didFinish = true
                    onAdd([block])
                    if onClose == nil { dismiss() }
                },
                onClose: { if let onClose { onClose() } else { dismiss() } }
            )
        }
    }
}
