import SwiftUI

/// Reorders or edits only the planned workout structure. It never alters
/// recorded sets, completed workouts or HealthKit data.
enum ATHLTHWorkoutBlockEditing {
    static func normalized(_ blocks: [WorkoutTemplateBlock]) -> [WorkoutTemplateBlock] {
        blocks.enumerated().map { index, block in
            WorkoutTemplateBlock(
                sequence: index + 1,
                kind: block.kind,
                title: block.title,
                exerciseSlug: block.exerciseSlug,
                distanceMeters: block.distanceMeters,
                repetitions: block.repetitions,
                durationSeconds: block.durationSeconds,
                targetWeightKilograms: block.targetWeightKilograms,
                loadNote: block.loadNote,
                notes: block.notes
            )
        }
    }

    static func moved(
        _ blocks: [WorkoutTemplateBlock],
        from source: Int,
        to destination: Int
    ) -> [WorkoutTemplateBlock] {
        guard blocks.indices.contains(source),
              blocks.indices.contains(destination),
              source != destination else { return blocks }
        var result = blocks
        result.swapAt(source, destination)
        return normalized(result)
    }

    static func replacing(
        _ blocks: [WorkoutTemplateBlock],
        at index: Int,
        with replacement: WorkoutTemplateBlock
    ) -> [WorkoutTemplateBlock] {
        guard blocks.indices.contains(index) else { return blocks }
        var result = blocks
        result[index] = replacement
        return normalized(result)
    }

    static func removing(_ blocks: [WorkoutTemplateBlock], at index: Int)
        -> [WorkoutTemplateBlock] {
        guard blocks.indices.contains(index) else { return blocks }
        var result = blocks
        result.remove(at: index)
        return normalized(result)
    }

    static func appending(_ blocks: [WorkoutTemplateBlock], kind: WorkoutTemplateBlockKind)
        -> [WorkoutTemplateBlock] {
        // Advanced running intervals, structured strength sets and the
        // remaining sport types still use their dedicated supported builders.
        // A generic note/rest block must not masquerade as one of those.
        // An otherwise unstructured workout must not accidentally be
        // reclassified as a structured recording by adding a lone note.
        guard !blocks.isEmpty,
              kind == .rest || kind == .note else { return blocks }
        var result = blocks
        result.append(
            WorkoutTemplateBlock(
                sequence: result.count + 1,
                kind: kind,
                title: kind == .rest
                    ? ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause")
                    : ATHLTHLocalization.choose(english: "Note", norwegian: "Notat"),
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: kind == .rest ? 60 : nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil
            )
        )
        return normalized(result)
    }
}

struct ATHLTHWorkoutBlockTimelineEditor: View {
    @Binding var blocks: [WorkoutTemplateBlock]
    @State private var selectedIndex: Int?
    @State private var draft: WorkoutTemplateBlock?
    @State private var showingEditSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "No structured blocks yet. Add a rest or note, or use the workout and exercise libraries for a complete session.",
                    norwegian: "Ingen strukturerte blokker ennå. Legg til pause eller notat, eller bruk økt- og øvelsesbiblioteket for en komplett økt."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                HStack(alignment: .center, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 24, height: 24)
                        .background(
                            ATHLTHTheme.champagneSoft,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    Image(systemName: block.kind.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 22)
                    Button {
                        selectedIndex = index
                        draft = block
                        showingEditSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            if let target = block.targetText {
                                Text(target)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button {
                            selectedIndex = index
                            draft = block
                            showingEditSheet = true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(english: "Edit block", norwegian: "Rediger blokk"),
                                systemImage: "pencil"
                            )
                        }

                        Button {
                            blocks = ATHLTHWorkoutBlockEditing.moved(blocks, from: index, to: index - 1)
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(english: "Move up", norwegian: "Flytt opp"),
                                systemImage: "arrow.up"
                            )
                        }
                        .disabled(index == 0)

                        Button {
                            blocks = ATHLTHWorkoutBlockEditing.moved(blocks, from: index, to: index + 1)
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(english: "Move down", norwegian: "Flytt ned"),
                                systemImage: "arrow.down"
                            )
                        }
                        .disabled(index == blocks.count - 1)

                        Button(role: .destructive) {
                            blocks = ATHLTHWorkoutBlockEditing.removing(blocks, at: index)
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(english: "Remove block", norwegian: "Fjern blokk"),
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 34, height: 40)
                    }
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Actions for \(block.title)",
                        norwegian: "Handlinger for \(block.title)"
                    ))
                }
                .padding(.vertical, 7)
            }

            if !blocks.isEmpty {
            Menu {
                Button {
                    blocks = ATHLTHWorkoutBlockEditing.appending(blocks, kind: .rest)
                } label: {
                    Label(
                        ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause"),
                        systemImage: "pause"
                    )
                }
                Button {
                    blocks = ATHLTHWorkoutBlockEditing.appending(blocks, kind: .note)
                } label: {
                    Label(
                        ATHLTHLocalization.choose(english: "Note", norwegian: "Notat"),
                        systemImage: "note.text"
                    )
                }
            } label: {
                Label(
                    ATHLTHLocalization.choose(english: "Add block", norwegian: "Legg til blokk"),
                    systemImage: "plus.circle"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let draft, let selectedIndex {
                ATHLTHWorkoutBlockDetailEditor(block: draft) { updated in
                    blocks = ATHLTHWorkoutBlockEditing.replacing(
                        blocks, at: selectedIndex, with: updated
                    )
                    showingEditSheet = false
                }
            }
        }
    }
}

private struct ATHLTHWorkoutBlockDetailEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutTemplateBlock
    let onSave: (WorkoutTemplateBlock) -> Void

    init(block: WorkoutTemplateBlock, onSave: @escaping (WorkoutTemplateBlock) -> Void) {
        _draft = State(initialValue: block)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        ATHLTHLocalization.choose(english: "Block name", norwegian: "Blokknavn"),
                        text: $draft.title
                    )
                    if draft.kind == .rest || draft.durationSeconds != nil {
                        Stepper(value: Binding(
                            get: { Int(draft.durationSeconds ?? 60) },
                            set: { draft.durationSeconds = TimeInterval($0) }
                        ), in: 15...7200, step: 15) {
                            Text("\(Int(draft.durationSeconds ?? 60)) sek")
                        }
                    }
                    if draft.repetitions != nil {
                        Stepper(value: Binding(
                            get: { draft.repetitions ?? 1 },
                            set: { draft.repetitions = $0 }
                        ), in: 1...1000) {
                            Text("\(draft.repetitions ?? 1) reps")
                        }
                    }
                    TextField(
                        ATHLTHLocalization.choose(english: "Notes", norwegian: "Notater"),
                        text: Binding(
                            get: { draft.notes ?? "" },
                            set: { draft.notes = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Block details",
                        norwegian: "Blokkdetaljer"
                    ))
                }
                if draft.exerciseSlug != nil {
                    Section {
                        Text(ATHLTHLocalization.choose(
                            english: "The exercise library reference remains unchanged.",
                            norwegian: "Koblingen til øvelsesbiblioteket beholdes uendret."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Edit block",
                norwegian: "Rediger blokk"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
