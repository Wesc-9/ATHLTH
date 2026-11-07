import Foundation
import NaturalLanguage

/// Detects the language of each individual Coach question. Chat response
/// language must not be tied to the selected ATHLTH interface language.
enum ATHLTHCoachMessageLanguage {
    static func responseCode(for question: String) -> String {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallbackCode }

        // Short prompts like "Hva bør jeg trene?" are common. NaturalLanguage
        // can have low confidence on short questions, so unambiguous words
        // and Norwegian letters take priority over the statistical fallback.
        let lower = text.lowercased()
        if lower.contains(where: { "æøå".contains($0) }) {
            return "nb"
        }

        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let norwegian: Set<String> = [
            "hva", "hvordan", "hvorfor", "hvilken", "hvilke", "burde",
            "trene", "trening", "økt", "øvelser", "jeg", "meg", "skal",
            "takk", "gjerne", "løpe", "styrke", "restitusjon", "norsk"
        ]
        let english: Set<String> = [
            "what", "how", "why", "should", "would", "could", "please",
            "workout", "train", "running", "strength", "today",
            "tomorrow", "my", "your", "english", "thanks"
        ]

        let norwegianCount = words.intersection(norwegian).count
        let englishCount = words.intersection(english).count
        if norwegianCount > englishCount { return "nb" }
        if englishCount > norwegianCount { return "en" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        switch recognizer.dominantLanguage?.rawValue {
        case "nb", "nn", "no": return "nb"
        case "en": return "en"
        default: return fallbackCode
        }
    }

    private static var fallbackCode: String {
        // For language-neutral inputs like "4x4" there is no detectable
        // language; only these cases use the app language as a fallback.
        ATHLTHLocalization.isNorwegian ? "nb" : "en"
    }
}
