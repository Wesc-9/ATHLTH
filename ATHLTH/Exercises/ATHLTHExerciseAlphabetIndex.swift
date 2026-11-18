import SwiftUI

/// One reusable A–Å index for the exercise library, its workout pickers and
/// Train's library surface. All lists provide stable exercise IDs and use the
/// same localized alphabetical ordering.
enum ATHLTHExerciseAlphabet {
    static let letters: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅ")
        .map(String.init)
    static let locale = Locale(identifier: "nb_NO")

    static func letter(for name: String) -> String {
        guard let first = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).first else { return "#" }
        let character = String(first).uppercased(with: locale)
        return letters.contains(character) ? character : "#"
    }

    static func firstIDs(
        for entries: [ExerciseLibraryEntry],
        name: (ExerciseLibraryEntry) -> String
    ) -> [String: UUID] {
        var first: [String: UUID] = [:]
        for entry in entries {
            let letter = letter(for: name(entry))
            if first[letter] == nil { first[letter] = entry.id }
        }
        return first
    }
}

/// Jump directly to any matching letter without mounting all earlier pages.
/// The dataset is already filtered and alphabetized by ExerciseLibraryStore.
/// This keeps at most the requested page in the on-screen lazy grid.
enum ATHLTHExerciseAlphabetPage {
    static func startIndex(
        for targetID: UUID,
        in entries: [ExerciseLibraryEntry]
    ) -> Int? {
        entries.firstIndex { $0.id == targetID }
    }

    static func visibleEntries(
        from entries: [ExerciseLibraryEntry],
        startIndex: Int,
        limit: Int
    ) -> [ExerciseLibraryEntry] {
        Array(entries.dropFirst(max(0, startIndex)).prefix(max(0, limit)))
    }

    static func remainingCount(total: Int, startIndex: Int) -> Int {
        max(0, total - max(0, startIndex))
    }
}

/// Locale-aware, stable A–Å ordering for entire library datasets, BEFORE
/// filtering to a 50-row display window. Retain original order for ties.
enum ATHLTHLibraryAlphabetSort {
    static func sorted<Item>(
        _ items: [Item],
        title: (Item) -> String
    ) -> [Item] {
        items.enumerated().sorted { lhs, rhs in
            let comparison = title(lhs.element).compare(
                title(rhs.element),
                options: [.caseInsensitive, .numeric],
                locale: ATHLTHExerciseAlphabet.locale
            )
            return comparison == .orderedSame
                ? lhs.offset < rhs.offset
                : comparison == .orderedAscending
        }.map(\.element)
    }
}

/// One shared A–Å lookup for all LOCAL library collections. Build targets
/// from the complete filtered result, not the current 50 rendered records.
/// The stable ID→index map allows jumps without loading intermediate pages.
struct ATHLTHLibraryAlphabetLookup<ID: Hashable> {
    let targets: [String: ID]
    private let indices: [ID: Int]

    init<Item>(items: [Item], id: (Item) -> ID, title: (Item) -> String) {
        var first: [String: ID] = [:]
        var positions: [ID: Int] = [:]
        for (offset, item) in items.enumerated() {
            let itemID = id(item)
            let letter = ATHLTHExerciseAlphabet.letter(for: title(item))
            if first[letter] == nil {
                first[letter] = itemID
                positions[itemID] = offset
            }
        }
        targets = first
        indices = positions
    }

    func index(for targetID: ID) -> Int? { indices[targetID] }
}

enum ATHLTHLibraryAlphabetWindow {
    static func visible<Item>(_ items: [Item], start: Int, limit: Int) -> [Item] {
        Array(items.dropFirst(max(0, start)).prefix(max(0, limit)))
    }

    static func remaining(total: Int, start: Int) -> Int {
        max(0, total - max(0, start))
    }
}

struct ATHLTHExerciseAlphabetIndex<ID: Hashable>: View {
    let targets: [String: ID]
    let onJump: (ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ATHLTHExerciseAlphabet.letters, id: \.self) { letter in
                let target = targets[letter]
                Button {
                    if let target { onJump(target) }
                } label: {
                    Text(letter)
                        .font(.system(
                            size: 9,
                            weight: target == nil ? .medium : .bold,
                            design: .rounded
                        ))
                        .foregroundStyle(
                            target == nil
                                ? ATHLTHTheme.mutedText.opacity(0.36)
                                : ATHLTHTheme.accentDeep
                        )
                        .frame(minWidth: 25, minHeight: 15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(target == nil)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Jump to items beginning with \(letter)",
                    norwegian: "Hopp til bokstaven \(letter)"
                ))
                .accessibilityAddTraits(target == nil ? [] : [.isButton])
            }
        }
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.65), lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.05), radius: 7, y: 2)
        .accessibilityElement(children: .contain)
    }
}
