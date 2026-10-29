import SwiftUI

/// One preview for every ATHLTH workout source: personal, planned, running,
/// strength, imported, mobility, cycling and hybrid. Never maintain separate
/// per-activity arrays of "exercises" in the selection UI. The unified
/// PlannedSession recipe is the single source of truth.
struct ATHLTHWorkoutContentsPreview: View {
    let workout: PlannedSession
    var maximumVisibleBlocks: Int? = 3

    private var blocks: [WorkoutTemplateBlock] {
        workout.resolvedWorkoutBlocks
    }

    private var visible: [WorkoutTemplateBlock] {
        Array(blocks.prefix(maximumVisibleBlocks ?? blocks.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(ATHLTHLocalization.choose(
                    english: "EXERCISES & STEPS", norwegian: "ØVELSER OG ØKTDELER"
                ))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Spacer(minLength: 0)

                if !blocks.isEmpty {
                    Text("\(blocks.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }

            if visible.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "No exercises or steps in this workout yet. Add them in the shared workout builder.",
                    norwegian: "Ingen øvelser eller øktdeler lagt inn ennå. Legg dem til i den felles øktbyggeren."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            } else {
                ForEach(visible.indices, id: \.self) { index in
                    let block = visible[index]
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: block.kind.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .background(ATHLTHTheme.accentSoft, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 5) {
                                Text(block.resolvedPhase.title)
                                if let details = block.targetText, !details.isEmpty {
                                    Text("·")
                                    Text(details)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if blocks.count > visible.count {
                    Text(ATHLTHLocalization.choose(
                        english: "+ \(blocks.count - visible.count) more steps",
                        norwegian: "+ \(blocks.count - visible.count) øktdeler"
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Before copying an existing workout into the user's schedule, inspect the
/// real shared recipe. Confirming returns the original PlannedSession to the
/// existing editor, where the athlete can freely change sets, rests and pace.
struct ATHLTHWorkoutSelectionPreviewSheet: View {
    let workout: PlannedSession
    let onUse: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    HStack(spacing: 14) {
                        Image(systemName: workout.kind.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 57, height: 57)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.title)
                                .font(.title2.bold())
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            if let duration = workout.durationMinutes {
                                Label("\(duration) min", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }
                    if let notes = workout.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    ATHLTHWorkoutContentsPreview(
                        workout: workout,
                        maximumVisibleBlocks: nil
                    )
                    .padding(17)
                    .background(
                        .white, in: RoundedRectangle(cornerRadius: 20)
                    )

                    Text(ATHLTHLocalization.choose(
                        english: "You can edit every exercise, interval, target and rest in the existing workout builder. This never overwrites the source workout.",
                        norwegian: "Du kan endre alle øvelser, intervaller, mål og pauser i den eksisterende øktbyggeren. Originaløkten endres ikke."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Workout contents", norwegian: "Øktinnhold"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: onUse) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Use this workout", norwegian: "Bruk denne økten"
                        ),
                        systemImage: "checkmark"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .padding(16)
                .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Back", norwegian: "Tilbake"
                    )) {
                        dismiss()
                    }
                }
            }
        }
    }
}
