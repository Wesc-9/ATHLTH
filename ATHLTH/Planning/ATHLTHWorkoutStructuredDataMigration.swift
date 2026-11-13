import Foundation

/// Lossless, read-time upgrade for legacy catalogue copies that previously
/// hid author-prescribed targets in a single note. Only exact ATHLTH-generated
/// field labels are recognized. Unfamiliar/free-form coaching notes survive
/// untouched, and a pre-existing typed value always takes precedence.
enum ATHLTHWorkoutStructuredDataMigration {
    static func normalize(_ source: WorkoutTemplateBlock) -> WorkoutTemplateBlock {
        guard let notes = source.notes, !notes.isEmpty else { return source }
        var block = source
        let segments = notes.components(separatedBy: " · ")
        var instructions: [String] = []

        for segment in segments {
            let text = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            // Zoned <= 2.2.0 stored exactly these keys in its instructions.
            if let value = numericValue(text, labels: ["VMA target:", "VMA-mål:"],
                                        suffix: "%") {
                if block.targetVMAPercent == nil { block.targetVMAPercent = value }
                continue
            }
            if let value = numericValue(text, labels: ["Elevation gain:", "Høydemeter:"],
                                        suffix: "m") {
                if block.targetElevationGainMeters == nil {
                    block.targetElevationGainMeters = value
                }
                continue
            }
            if let value = numericValue(text, labels: ["Gradient:", "Stigning:"],
                                        suffix: "%") {
                if block.targetGradientPercent == nil { block.targetGradientPercent = value }
                continue
            }
            if let value = labelledValue(
                text, labels: ["Pace intensity:", "Fartsintensitet:"]
            ) {
                if block.targetIntensityType == nil {
                    block.targetIntensityType = value
                }
                continue
            }
            if let value = labelledValue(text, labels: ["Terrain:", "Terreng:"]) {
                if block.targetTerrainType == nil { block.targetTerrainType = value }
                continue
            }

            // Old source-authored strength prescriptions:
            // "8–12 reps", "8–12 repetisjoner", "8–12 per set", "8–12 per sett".
            // Do not attempt to interpret general notes or user-written text.
            if block.kind == .exercise,
               let reps = authoredRepRange(text) {
                if block.repetitions == nil { block.repetitions = reps.lower }
                if block.targetRepetitionsMaximum == nil {
                    block.targetRepetitionsMaximum = reps.upper
                }
                continue
            }
            if block.kind == .exercise, let rir = authoredRIR(text) {
                if block.targetRepsInReserve == nil {
                    block.targetRepsInReserve = rir.value
                }
                if !rir.remaining.isEmpty { instructions.append(rir.remaining) }
                continue
            }
            instructions.append(segment)
        }

        block.notes = instructions.isEmpty ? nil : instructions.joined(separator: " · ")
        return block
    }

    private static func labelledValue(
        _ text: String, labels: [String]
    ) -> String? {
        guard let label = labels.first(where: { text.hasPrefix($0) }) else {
            return nil
        }
        let value = text.dropFirst(label.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return nil }
        return value
    }

    private static func numericValue(
        _ text: String, labels: [String], suffix: String
    ) -> Double? {
        guard let value = labelledValue(text, labels: labels),
              value.hasSuffix(suffix) else { return nil }
        let raw = value.dropLast(suffix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let number = Double(raw), number.isFinite,
              (0...10000).contains(number) else { return nil }
        return number
    }

    private static func authoredRepRange(
        _ text: String
    ) -> (lower: Int, upper: Int)? {
        let pattern = #"^(\d{1,3})[–-](\d{1,3}) (?:reps|repetisjoner|per set|per sett)$"#
        guard let parts = groups(text, pattern: pattern), parts.count == 2,
              let low = Int(parts[0]), let high = Int(parts[1]),
              (1...100).contains(low), low <= high, high <= 100 else {
            return nil
        }
        return (low, high)
    }

    private static func authoredRIR(
        _ text: String
    ) -> (value: Int, remaining: String)? {
        let prefixes = [
            " reps in reserve (RIR). ", " repetisjoner i reserve (RIR). ",
            " reps in reserve", " i reserve"
        ]
        for prefix in prefixes {
            guard let match = groups(
                text,
                pattern: #"^(\d{1,2})"# + NSRegularExpression.escapedPattern(for: prefix)
            ), let digits = match.first, let rir = Int(digits),
              (0...10).contains(rir) else { continue }
            let length = digits.count + prefix.count
            let remaining = String(text.dropFirst(length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (rir, remaining)
        }
        return nil
    }

    private static func groups(_ source: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: source, range: NSRange(source.startIndex..., in: source)
              ), match.range.location == 0
        else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            guard let range = Range(match.range(at: $0), in: source) else {
                return nil
            }
            return String(source[range])
        }
    }
}

extension Array where Element == WorkoutTemplateBlock {
    /// Non-destructive upgrade; the user's stored plan remains unchanged until
    /// an explicit edit/save. In particular, no guessed zone/pace/weight values.
    func recoveringLegacyStructuredTargets() -> [WorkoutTemplateBlock] {
        map(ATHLTHWorkoutStructuredDataMigration.normalize)
    }
}
