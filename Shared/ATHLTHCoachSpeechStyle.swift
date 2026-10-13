import Foundation
import AVFoundation

/// The words used by Audio Coach, deliberately independent of voice speed,
/// how frequently cues occur and which sensor values are announced.
/// Added to transfer payloads as an optional field for older Watch builds.
enum ATHLTHCoachSpeechStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case balanced
    case motivating
    case technical
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return ATHLTHLocalization.choose(
                english: "Balanced", norwegian: "Balansert"
            )
        case .motivating:
            return ATHLTHLocalization.choose(
                english: "Motivating", norwegian: "Motiverende"
            )
        case .technical:
            return ATHLTHLocalization.choose(
                english: "Technical", norwegian: "Teknisk"
            )
        case .minimal:
            return ATHLTHLocalization.choose(
                english: "Minimal", norwegian: "Minimal"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .balanced:
            return ATHLTHLocalization.choose(
                english: "Natural and calm", norwegian: "Naturlig og rolig"
            )
        case .motivating:
            return ATHLTHLocalization.choose(
                english: "Positive encouragement", norwegian: "Positiv oppmuntring"
            )
        case .technical:
            return ATHLTHLocalization.choose(
                english: "Clear training data", norwegian: "Tydelige treningsdata"
            )
        case .minimal:
            return ATHLTHLocalization.choose(
                english: "Shorter unit names", norwegian: "Kortere benevnelser"
            )
        }
    }

    /// Preserve urgent guidance verbatim: a style may never soften a route,
    /// target or Ghost warning. Numbers and other metrics are not recalculated.
    func render(
        _ phrase: String,
        language: WatchAudioCoachLanguage,
        priority: ATHLTHGuidancePriority,
        eventKind: ATHLTHCoachEventKind? = nil
    ) -> String {
        guard !phrase.isEmpty,
              priority == .routineCoach || priority == .structuredStep
        else { return phrase }

        // Rest countdowns and navigation transitions should remain concise
        // and actionable regardless of the selected personality.
        let isNeutralProgress =
            eventKind == .routineMilestone ||
            eventKind == .strengthSet ||
            eventKind == .manualStatus ||
            (eventKind == nil && priority == .routineCoach)

        let norwegian: Bool
        switch language {
        case .norwegian:
            norwegian = true
        case .english:
            norwegian = false
        case .system:
            let code = Locale.autoupdatingCurrent.language.languageCode?
                .identifier.lowercased()
            norwegian = code == "nb" || code == "nn" || code == "no"
        }

        switch self {
        case .balanced:
            return phrase
        case .motivating:
            guard isNeutralProgress else { return phrase }
            let encouragement = norwegian ? " Bra jobbet!" : " Nice work!"
            return phrase.hasSuffix(encouragement)
                ? phrase
                : phrase + encouragement
        case .technical:
            guard isNeutralProgress else { return phrase }
            let prefix = norwegian ? "Øktdata: " : "Workout data: "
            return phrase.hasPrefix(prefix)
                ? phrase
                : prefix + phrase
        case .minimal:
            // Never omit pace, heart rate, distance or current step.
            // Using abbreviated units shortens delivery without changing facts.
            var text = phrase
            for (full, brief) in [
                ("kilometers", "km"),
                ("kilometer", "km"),
                ("minutes", "min"),
                ("minutter", "min"),
                ("seconds", "s"),
                ("sekunder", "s"),
                ("meters", "m"),
                ("meter", "m")
            ] {
                text = text.replacingOccurrences(
                    of: "\\b" + full + "\\b",
                    with: brief,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            return text
        }
    }
}


/// Uses the best compatible system voice installed on the actual speaker.
/// User-selected voices are never overridden. No cloud request is required.
enum ATHLTHCoachPreferredSystemVoice {
    static func resolve(
        selectedIdentifier: String?,
        language: WatchAudioCoachLanguage
    ) -> AVSpeechSynthesisVoice? {
        if let selectedIdentifier,
           let preferred = AVSpeechSynthesisVoice(identifier: selectedIdentifier) {
            return preferred
        }
        let code: String
        switch language {
        case .norwegian: code = "nb"
        case .english: code = "en"
        case .system:
            code = Locale.autoupdatingCurrent.language.languageCode?
                .identifier.lowercased() ?? "en"
        }
        let norwegian = ["nb", "nn", "no"].contains(code)
        let prefixes = norwegian ? ["nb", "nn", "no"] : [code]
        let preferredLocale = norwegian ? "nb-no" :
            (code == "en" ? "en-us" : code)
        let available = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            let locale = voice.language.lowercased()
            return prefixes.contains { locale.hasPrefix($0) }
        }
        let best = available.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            let leftExact = lhs.language.lowercased() == preferredLocale
            let rightExact = rhs.language.lowercased() == preferredLocale
            if leftExact != rightExact { return leftExact }
            return lhs.identifier < rhs.identifier
        }.first

        return best ?? AVSpeechSynthesisVoice(
            language: norwegian ? "nb-NO" :
                (code == "en" ? "en-US" : code)
        )
    }
}
