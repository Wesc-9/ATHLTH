import Foundation

/// Structured manual repetition results. These are descriptions submitted
/// for participant consensus, never independently attested workout metrics.
enum ATHLTHArenaRepetitionResult {
    static func agreedExercise(in rules: String) -> String? {
        guard let first = rules.components(separatedBy: .newlines).first else {
            return nil
        }
        let prefix = "Øvelse:"
        guard first.hasPrefix(prefix) else { return nil }
        let name = String(first.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func explanation(
        exercise: String,
        repetitions: [String],
        optionalNote: String
    ) -> String? {
        let name = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              !repetitions.isEmpty, repetitions.count <= 3
        else { return nil }
        var lines: [String] = ["Øvelse: " + name]
        for (index, raw) in repetitions.enumerated() {
            let number = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let count = Int(number), (1...100_000).contains(count)
            else { return nil }
            lines.append("\(index + 1). plass: \(count) repetisjoner")
        }
        let note = optionalNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { lines.append("Kommentar: " + note) }
        let result = lines.joined(separator: "\n")
        return result.count <= 600 ? result : nil
    }
}
