import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ATHLTHIntelligenceProvider: String, CaseIterable, Sendable {
    case rules, appleLocal, appleCloud, groq, openAIRealtime

    var title: String {
        switch self {
        case .rules: return "ATHLTH"
        case .appleLocal: return "Apple · On-device"
        case .appleCloud: return "Apple · Private Cloud Compute"
        case .groq: return "Groq"
        case .openAIRealtime: return "OpenAI Realtime"
        }
    }
}

/// Explicit feature routing: do not infer consent from a provider's availability.
/// The only new route in this release is a synthetic administrator diagnostic.
enum ATHLTHIntelligenceFeature: String, CaseIterable, Sendable {
    case dailyFormCalculation, dailyRecommendation, fixedAudioCoach
    case workoutInsight, recoveryInsight, coachQuestion, trainingProgram
    case strengthSession, planAdaptation, equipmentRecognition, pushToTalk
    case realtimeConversation, localDiagnostic

    var title: String {
        switch self {
        case .dailyFormCalculation: return "Daily form calculation"
        case .dailyRecommendation: return "Daily recommendation"
        case .fixedAudioCoach: return "Fixed audio cues"
        case .workoutInsight: return "Workout insight"
        case .recoveryInsight: return "Recovery insight"
        case .coachQuestion: return "Coach question"
        case .trainingProgram: return "Training program"
        case .strengthSession: return "Strength session"
        case .planAdaptation: return "Plan adaptation"
        case .equipmentRecognition: return "Equipment recognition"
        case .pushToTalk: return "Push-to-talk pilot"
        case .realtimeConversation: return "Realtime conversation"
        case .localDiagnostic: return "Local AI diagnostic"
        }
    }
}

enum ATHLTHIntelligenceRoutingPolicy {
    static func provider(for feature: ATHLTHIntelligenceFeature,
                         adminPilotEnabled: Bool = false,
                         isAdministrator: Bool = false,
                         localAvailable: Bool = false) -> ATHLTHIntelligenceProvider? {
        switch feature {
        case .dailyFormCalculation, .dailyRecommendation, .fixedAudioCoach:
            return .rules
        case .workoutInsight, .recoveryInsight, .coachQuestion, .trainingProgram,
             .strengthSession, .planAdaptation, .equipmentRecognition, .pushToTalk:
            return .groq
        case .realtimeConversation:
            return .openAIRealtime
        case .localDiagnostic:
            // No remote fallback: a local-only request must stay local.
            return adminPilotEnabled && isAdministrator && localAvailable ? .appleLocal : nil
        }
    }

    // The managed entitlement and a verified release configuration are needed
    // before adding a PCC adapter. An admin toggle cannot grant this access.
    static let cloudEnabled = false
}

enum ATHLTHIntelligenceDiagnosticError: Error {
    case unavailable, invalidResponse
}

struct ATHLTHIntelligenceDiagnosticResult: Sendable {
    let provider: ATHLTHIntelligenceProvider
    let text: String
    let elapsedMilliseconds: Int
}

@MainActor
enum ATHLTHIntelligenceEngine {
    static var isLocalAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Synthetic data only; no HealthKit, identity, workout, prompt history
    /// or network fallback. No session is allocated until an explicit tap.
    static func runLocalDiagnostic(enabled: Bool, isAdministrator: Bool,
                                   norwegian: Bool) async throws -> ATHLTHIntelligenceDiagnosticResult {
        guard ATHLTHIntelligenceRoutingPolicy.provider(for: .localDiagnostic,
            adminPilotEnabled: enabled, isAdministrator: isAdministrator,
            localAvailable: isLocalAvailable) == .appleLocal else {
            throw ATHLTHIntelligenceDiagnosticError.unavailable
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let start = ContinuousClock.now
            let session = LanguageModelSession(instructions: """
                You are testing a sports app's language support using a fictional example.
                Paraphrase only the supplied sentence. Keep the duration and activity unchanged.
                No new facts, training instructions, health advice, headings or lists.
                """)
            let prompt = norwegian
                ? "Skriv én kort, naturlig setning på norsk bokmål: Eksempeløkten var en gåtur på 30 minutter."
                : "Write one short natural English sentence: The example workout was a 30-minute walk."
            let response = try await session.respond(to: prompt)
            try Task.checkCancellation()
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard validatesDiagnostic(text, norwegian: norwegian) else {
                throw ATHLTHIntelligenceDiagnosticError.invalidResponse
            }
            let duration = start.duration(to: .now).components
            let ms = Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000)
            return ATHLTHIntelligenceDiagnosticResult(provider: .appleLocal,
                text: text, elapsedMilliseconds: max(0, ms))
        }
        #endif
        throw ATHLTHIntelligenceDiagnosticError.unavailable
    }

    static func validatesDiagnostic(_ text: String, norwegian: Bool) -> Bool {
        guard !text.isEmpty, text.count <= 220, !text.contains("\n") else { return false }
        let lower = text.lowercased()
        let numbers = lower.split(whereSeparator: { !$0.isNumber })
        guard numbers.count == 1, numbers.first == "30" else { return false }
        return norwegian
            ? (lower.contains("gåtur") || lower.contains("gikk") || lower.contains("gåing") || lower.contains("spasertur")) && lower.contains("minutt")
            : lower.contains("walk") && lower.contains("minute")
    }
}
