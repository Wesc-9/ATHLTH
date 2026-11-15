import Foundation

/// Fast, local suggestions from the exercise catalog; keeps free-text input
/// available when an athlete owns a machine absent from the library.
enum ATHLTHExerciseEquipmentSuggestions {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "nb_NO"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
    }

    static func suggestions(
        for text: String,
        options: [String],
        localizedTitle: (String) -> String,
        limit: Int = 5
    ) -> [String] {
        let key = normalized(text)
        guard key.count >= 2 else { return [] }
        return options.compactMap { option -> (String, Int)? in
            let names = [normalized(option), normalized(localizedTitle(option))]
            var score: Int?
            for name in names {
                guard !name.isEmpty else { continue }
                let candidate: Int?
                if name == key { candidate = 0 }
                else if name.hasPrefix(key) { candidate = 1 }
                else if name.split(separator: " ").contains(where: {
                    $0.hasPrefix(key)
                }) { candidate = 2 }
                else if name.contains(key) { candidate = 3 }
                else if key.count >= 4 &&
                        abs(name.count - key.count) <= 2 &&
                        editDistanceAtMostTwo(key, name) {
                    candidate = 4
                } else {
                    candidate = nil
                }
                if let candidate {
                    score = min(score ?? candidate, candidate)
                }
            }
            return score.map { (option, $0) }
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return localizedTitle($0.0).localizedStandardCompare(
                localizedTitle($1.0)
            ) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
    }

    private static func editDistanceAtMostTwo(_ left: String,
                                               _ right: String) -> Bool {
        let a = Array(left), b = Array(right)
        guard abs(a.count - b.count) <= 2 else { return false }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var next = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                next[j] = min(
                    previous[j] + 1, next[j - 1] + 1,
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
            }
            if (next.min() ?? 3) > 2 { return false }
            previous = next
        }
        return previous[b.count] <= 2
    }
}
