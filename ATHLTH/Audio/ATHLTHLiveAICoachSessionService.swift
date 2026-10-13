import Foundation
import Supabase

/// Phase 1 only: requests a short-lived voice session credential after an
/// explicit confirmation in the future microphone UI. No microphone is opened
/// and no HealthKit values are uploaded by this service.
struct ATHLTHLiveAICoachSessionToken: Decodable {
    let token: String
    let expiresAt: TimeInterval
    let model: String

    var isExpired: Bool {
        Date().timeIntervalSince1970 >= expiresAt
    }
}

enum ATHLTHLiveAICoachError: LocalizedError {
    case consentRequired
    case invalidSession

    var errorDescription: String? {
        switch self {
        case .consentRequired:
            return ATHLTHLocalization.choose(
                english: "Confirm microphone and AI voice processing first.",
                norwegian: "Bekreft bruk av mikrofon og AI-behandling av tale først."
            )
        case .invalidSession:
            return ATHLTHLocalization.choose(
                english: "The AI voice session could not start.",
                norwegian: "Kunne ikke starte AI-talesamtalen."
            )
        }
    }
}

@MainActor
final class ATHLTHLiveAICoachSessionService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func requestToken(
        microphoneConsent: Bool,
        aiAudioProcessingConsent: Bool,
        language: WatchAudioCoachLanguage,
        speechStyle: ATHLTHCoachSpeechStyle
    ) async throws -> ATHLTHLiveAICoachSessionToken {
        guard microphoneConsent && aiAudioProcessingConsent else {
            throw ATHLTHLiveAICoachError.consentRequired
        }

        let languageCode: String
        switch language {
        case .norwegian: languageCode = "no"
        case .english: languageCode = "en"
        case .system:
            let code = Locale.autoupdatingCurrent.language.languageCode?
                .identifier.lowercased() ?? "en"
            languageCode = ["nb", "nn", "no"].contains(code) ? "no" : "en"
        }
        let request = SessionRequest(
            microphoneConsent: true,
            aiAudioProcessingConsent: true,
            language: languageCode,
            tone: speechStyle == .motivating ? "motivating" : "balanced"
        )
        let session: ATHLTHLiveAICoachSessionToken =
            try await client.functions.invoke(
                "create-audio-coach-session",
                options: FunctionInvokeOptions(body: request)
            )
        guard !session.isExpired, !session.token.isEmpty else {
            throw ATHLTHLiveAICoachError.invalidSession
        }
        return session
    }

    private struct SessionRequest: Encodable {
        let microphoneConsent: Bool
        let aiAudioProcessingConsent: Bool
        let language: String
        let tone: String
    }
}
