import CryptoKit
import Foundation
import SwiftUI
import Translation

/// On-device translation of RepDB's English catalog into Norwegian Bokmål.
///
/// Canonical RepDB records, exercise identifiers and media never change. The
/// system manages its own language model; ATHLTH only persists translated
/// UTF-8 strings (rather than shipping a second 643-exercise database).
///
/// Reviewed Norwegian strings from ExerciseNames/ExerciseDetails take
/// precedence over these unreviewed system translations.
@MainActor
final class NorwegianExerciseAutoTranslation: ObservableObject {
    static let shared = NorwegianExerciseAutoTranslation()

    @Published private(set) var revision = 0

    private var translatedValues: [String: String] = [:]

    private static let cacheURL: URL? = {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("Localizations", isDirectory: true)
            .appendingPathComponent("repdb-en-nb-v1.json")
    }()

    private init() {
        if let file = Self.cacheURL,
           let data = try? Data(contentsOf: file),
           data.count < 8_000_000,
           let values = try? JSONDecoder().decode(
               [String: String].self, from: data
           ) {
            translatedValues = values
        }
    }

    static func configuration() -> TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "nb")
        )
    }

    static func availabilityStatus() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "nb")
        )
    }

    func translated(_ english: String) -> String? {
        guard ATHLTHLocalization.isNorwegian else { return nil }
        return translatedValues[Self.key(for: english)]
    }

    private static func key(for english: String) -> String {
        SHA256.hash(data: Data(english.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var cachedStringCount: Int { translatedValues.count }

    /// Translate only strings absent from the cache, in small batches to
    /// avoid stalling the exercise list or keeping long texts resident.
    /// Failures preserve English originals; no guessed technique is shown.
    func translate(
        texts: [String],
        using session: TranslationSession,
        batchSize: Int = 25
    ) async {
        guard ATHLTHLocalization.isNorwegian else { return }
        var seen = Set<String>()
        let missing = texts.filter { text in
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 1_500,
                  translatedValues[Self.key(for: text)] == nil
            else { return false }
            return seen.insert(text).inserted
        }

        for start in stride(from: 0, to: missing.count, by: max(1, batchSize)) {
            if Task.isCancelled { return }
            let end = min(start + max(1, batchSize), missing.count)
            let batch = Array(missing[start..<end])
            let requests = batch.enumerated().map { index, original in
                TranslationSession.Request(
                    sourceText: original,
                    clientIdentifier: String(index)
                )
            }
            var updates: [String: String] = [:]
            do {
                for try await response in session.translate(batch: requests) {
                    guard let value = response.clientIdentifier,
                          let index = Int(value),
                          batch.indices.contains(index) else { continue }
                    let norwegian = response.targetText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let original = batch[index]
                    guard !norwegian.isEmpty,
                          norwegian != original,
                          norwegian.count < original.count * 5 + 100 else {
                        continue
                    }
                    updates[Self.key(for: original)] = norwegian
                }
            } catch {
                // When system language support is unavailable or interrupted,
                // keep the original text and retry only on explicit next use.
                return
            }
            if !updates.isEmpty {
                translatedValues.merge(updates) { _, new in new }
                revision &+= 1
                persist()
            }
        }
    }

    private func persist() {
        guard let file = Self.cacheURL,
              let data = try? JSONEncoder().encode(translatedValues),
              data.count < 8_000_000 else { return }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
        } catch {
            // Translations remain available in memory during this session.
        }
    }
}
