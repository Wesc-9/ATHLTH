import Foundation

/// A deliberately small, high-quality Apple voice selection for Audio Coach.
/// The source of truth remains the voices actually installed on this device.
struct ATHLTHCoachVoiceDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let qualityRank: Int
}

enum ATHLTHCoachVoiceCatalog {
    /// Premium/enhanced Apple voices only. Basic and novelty/effect voices are
    /// deliberately hidden; Automatic speech remains available independently.
    static func featured(
        from installed: [ATHLTHCoachVoiceDescriptor],
        languageCode: String
    ) -> [ATHLTHCoachVoiceDescriptor] {
        let code = languageCode.lowercased()
        let norwegian = ["nb", "nn", "no"].contains(code)
        let prefixes = norwegian ? ["nb", "nn", "no"] : [code]
        let limit = norwegian ? 4 : 3
        var shownNames = Set<String>()

        return Array(installed
            .filter { voice in
                let locale = voice.language.lowercased()
                return prefixes.contains(where: { locale.hasPrefix($0) })
                    && voice.qualityRank >= 2
                    && !isNovelty(name: voice.name)
            }
            .sorted { lhs, rhs in
                if lhs.qualityRank != rhs.qualityRank {
                    return lhs.qualityRank > rhs.qualityRank
                }
                let byName = lhs.name.localizedStandardCompare(rhs.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return lhs.id < rhs.id
            }
            .filter { voice in
                shownNames.insert(voice.name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )).inserted
            }
            .prefix(limit))
    }

    /// Apple also exposes character voices and sound effects as if they were
    /// ordinary narrators. They are unsuitable for pace and safety cues.
    static func isNovelty(name: String) -> Bool {
        let normalized = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return Set([
            "albert", "bad news", "good news", "bahh", "bells", "bjeller",
            "bubbles", "bobler", "boing", "cellos", "hysterical", "jester",
            "organ", "trinoids", "whisper", "wobble", "zarvox"
        ]).contains(normalized)
    }
}
