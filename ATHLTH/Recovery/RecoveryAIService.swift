import CryptoKit
import Foundation
import Supabase

struct RecoveryAIMuscleInput: Codable, Hashable {
    let name: String
    let recoveryPercent: Int
    let status: String
    let completedSets: Int
}

struct RecoveryAICheckIn: Codable, Hashable {
    let energy: Int?
    let stress: Int?
    let overallSoreness: Int?
    let motivation: Int?
}

struct RecoveryAIContext: Codable, Hashable {
    let recoveryScore: Int?
    let recoveryState: String
    let recoveryDetail: String
    let sleepSeconds: Double?
    let baselineSleepSeconds: Double?
    let hrvMilliseconds: Double?
    let baselineHRVMilliseconds: Double?
    let restingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let yesterdayTrainingMinutes: Double
    let acuteTrainingMinutes: Double
    let chronicWeeklyAverageMinutes: Double?
    let muscles: [RecoveryAIMuscleInput]
    let checkIn: RecoveryAICheckIn
}


extension RecoveryAIContext {
    // Deliberately empty health context for ordinary Coach questions.
    // This is the default for every request unless the user explicitly
    // confirms health-data sharing for that one message.
    static var withoutHealthData: RecoveryAIContext {
        RecoveryAIContext(
            recoveryScore: nil,
            recoveryState: "Not shared",
            recoveryDetail: "Health data was not shared for this question.",
            sleepSeconds: nil,
            baselineSleepSeconds: nil,
            hrvMilliseconds: nil,
            baselineHRVMilliseconds: nil,
            restingHeartRate: nil,
            baselineRestingHeartRate: nil,
            yesterdayTrainingMinutes: 0,
            acuteTrainingMinutes: 0,
            chronicWeeklyAverageMinutes: nil,
            muscles: [],
            checkIn: RecoveryAICheckIn(
                energy: nil,
                stress: nil,
                overallSoreness: nil,
                motivation: nil
            )
        )
    }
}

struct RecoveryAIFactor: Codable, Hashable, Identifiable {
    var id: String { title + detail }

    let title: String
    let detail: String
    let impact: String
}

struct RecoveryAISuggestion: Codable, Hashable {
    let title: String
    let subtitle: String
    let reason: String
}

struct RecoveryAIInsight: Codable, Hashable {
    let headline: String
    let summary: String
    let factors: [RecoveryAIFactor]
    let suggestion: RecoveryAISuggestion
    let quickQuestions: [String]
}

enum RecoveryCoachMessageRole:
    String,
    Codable,
    Hashable {
    case user
    case assistant
}

struct RecoveryCoachMessage:
    Identifiable,
    Codable,
    Hashable {
    let id: UUID
    let role: RecoveryCoachMessageRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: RecoveryCoachMessageRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct RecoveryCoachReply: Hashable {
    let answer: String
    let quickQuestions: [String]
}

struct RecoveryCoachConversationState:
    Codable,
    Hashable {
    var messages: [RecoveryCoachMessage]
    var quickQuestions: [String]
    var contextSignature: String?
}

private struct RecoveryAIChatTurn: Encodable {
    let role: String
    let content: String
}

private struct RecoveryAIRequest: Encodable {
    let mode: String
    let context: RecoveryAIContext
    let question: String?
    let language: String
    let history: [RecoveryAIChatTurn]?
    let shareHealthData: Bool?
}

// Separate, versioned first-use consent for automatic Insights AI.
// Legacy HealthKit/AI settings never authorize third-party processing.
struct RecoveryInsightAIConsentRecord: Codable, Equatable {
    let version: Int
    let decidedAt: Date
    let authorizedAt: Date?

    var allowsExternalHealthProcessing: Bool {
        authorizedAt != nil
    }
}

enum RecoveryInsightAIConsentPreferences {
    private static let version = 1

    private static func key(userID: UUID) -> String {
        "athlth.insights.externalAIHealthConsent.v1.\(userID.uuidString)"
    }

    static func load(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> RecoveryInsightAIConsentRecord? {
        guard let data = defaults.data(forKey: key(userID: userID)),
              let record = try? JSONDecoder().decode(
                  RecoveryInsightAIConsentRecord.self,
                  from: data
              ),
              record.version == version
        else {
            return nil
        }
        return record
    }

    static func isAuthorized(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        load(userID: userID, defaults: defaults)?
            .allowsExternalHealthProcessing == true
    }

    @discardableResult
    static func decide(
        userID: UUID,
        allowExternalHealthProcessing: Bool,
        defaults: UserDefaults = .standard
    ) -> RecoveryInsightAIConsentRecord {
        let prior = load(userID: userID, defaults: defaults)
        let record = RecoveryInsightAIConsentRecord(
            version: version,
            decidedAt: Date(),
            authorizedAt: allowExternalHealthProcessing
                ? (prior?.authorizedAt ?? Date())
                : nil
        )
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key(userID: userID))
        }
        // A fresh decision must not retain a legacy, backed-up AI cache.
        clearCachedInsight(userID: userID, defaults: defaults)
        return record
    }

    static func clearCachedInsight(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        // Remove legacy defaults cache and encrypted, non-backed-up files.
        for language in ["nb", "en"] {
            defaults.removeObject(
                forKey: "athlth.recoveryAIInsight.\(userID.uuidString).\(language)"
            )
            UserDefaults.standard.removeObject(
                forKey: "athlth.recoveryAIInsight.\(userID.uuidString).\(language)"
            )
        }
        RecoveryInsightProtectedCache.remove(userID: userID)
    }

    static func removeForDeletedAccount(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(userID: userID))
        clearCachedInsight(userID: userID, defaults: defaults)
    }
}

enum RecoveryInsightAIConsentError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        ATHLTHLocalization.choose(
            english: "Allow AI health insights before sharing health data with Groq.",
            norwegian: "Godkjenn AI-helseinnsikt før helsedata deles med Groq."
        )
    }
}

// Derived AI health insights should never be stored in backed-up defaults.
private enum RecoveryInsightProtectedCache {
    private static func fileURL(
        userID: UUID,
        language: String
    ) -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return base.appendingPathComponent(
            "recovery-insight-\(userID.uuidString)-\(language).json"
        )
    }

    static func load(userID: UUID, language: String) -> Data? {
        guard let url = fileURL(
            userID: userID,
            language: language
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func save(
        _ data: Data,
        userID: UUID,
        language: String
    ) {
        guard let url = fileURL(
            userID: userID,
            language: language
        ) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
            var protectedURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)
        } catch {
            // If protection or backup exclusion fails, keep no cache.
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func remove(userID: UUID) {
        for language in ["nb", "en"] {
            if let url = fileURL(
                userID: userID, language: language
            ) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

private struct RecoveryAIInsightCacheEntry: Codable {
    let signature: String
    let createdAt: Date
    let insight: RecoveryAIInsight
}

private struct RecoveryAICacheMuscle: Codable {
    let name: String
    let completedSets: Int
}

private struct RecoveryAICacheSignature: Codable {
    let recoveryScore: Int?
    let recoveryState: String
    let sleepSeconds: Double?
    let baselineSleepSeconds: Double?
    let hrvMilliseconds: Double?
    let baselineHRVMilliseconds: Double?
    let restingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let yesterdayTrainingMinutes: Double
    let acuteTrainingMinutes: Double
    let chronicWeeklyAverageMinutes: Double?
    let muscles: [RecoveryAICacheMuscle]
    let checkIn: RecoveryAICheckIn
}

private struct RecoveryAIAnswer: Decodable {
    let answer: String
    let quickQuestions: [String]?
}

enum RecoveryCoachInboxPreferences {
    private static func pinKey(
        userID: UUID
    ) -> String {
        "athlth.recoveryCoach.inboxPinned." +
        userID.uuidString
    }

    static func isPinned(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let key = pinKey(userID: userID)

        guard defaults.object(
            forKey: key
        ) != nil
        else {
            // Coach starts pinned for every account,
            // but the user can explicitly unpin it.
            return true
        }

        return defaults.bool(
            forKey: key
        )
    }

    static func setPinned(
        _ pinned: Bool,
        userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            pinned,
            forKey:
                pinKey(
                    userID: userID
                )
        )
    }
}

// Account-scoped, versioned record of the user's explicit Coach choices.
// An existing Apple Health permission or a global insights preference never
// counts as permission to disclose health data in this separate AI chat.
struct RecoveryCoachConsentRecord: Codable, Equatable {
    let version: Int
    let aiApprovedAt: Date
    let healthApprovedAt: Date?

    var healthSharingAllowed: Bool {
        healthApprovedAt != nil
    }
}

enum RecoveryCoachConsentPreferences {
    private static let version = 1

    private static func key(userID: UUID) -> String {
        "athlth.recoveryCoach.aiConsent.v1.\(userID.uuidString)"
    }

    static func load(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> RecoveryCoachConsentRecord? {
        guard let data = defaults.data(forKey: key(userID: userID)),
              let value = try? JSONDecoder().decode(
                  RecoveryCoachConsentRecord.self, from: data
              ),
              value.version == version
        else {
            return nil
        }
        return value
    }

    @discardableResult
    static func approve(
        userID: UUID,
        healthSharingAllowed: Bool,
        defaults: UserDefaults = .standard
    ) -> RecoveryCoachConsentRecord {
        let previous = load(userID: userID, defaults: defaults)
        let record = RecoveryCoachConsentRecord(
            version: version,
            aiApprovedAt: previous?.aiApprovedAt ?? Date(),
            healthApprovedAt: healthSharingAllowed
                ? (previous?.healthApprovedAt ?? Date())
                : nil
        )
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key(userID: userID))
        }
        return record
    }

    static func revoke(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(userID: userID))
    }
}

enum RecoveryCoachConversationPersistence {
    private static let maxStoredMessages = 200

    static func load(
        userID: UUID
    ) -> RecoveryCoachConversationState? {
        let url = conversationURL(
            userID: userID
        )

        guard let data =
                try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(
            RecoveryCoachConversationState.self,
            from: data
        )
    }

    static func save(
        _ state: RecoveryCoachConversationState,
        userID: UUID
    ) {
        let trimmed =
            RecoveryCoachConversationState(
                messages:
                    Array(
                        state.messages
                            .suffix(
                                maxStoredMessages
                            )
                    ),
                quickQuestions:
                    Array(
                        state.quickQuestions
                            .prefix(3)
                    ),
                contextSignature:
                    state.contextSignature
            )

        guard let data =
                try? JSONEncoder()
                    .encode(trimmed)
        else {
            return
        }

        let url =
            conversationURL(
                userID: userID
            )

        do {
            try FileManager.default
                .createDirectory(
                    at:
                        url
                            .deletingLastPathComponent(),
                    withIntermediateDirectories:
                        true
                )
            // Conversations may include health information voluntarily
            // entered by the user. Protect them while the device is locked
            // and keep this device-only cache out of system backups.
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
            var protectedURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try protectedURL.setResourceValues(resourceValues)
        } catch {
            return
        }
    }

    static func delete(userID: UUID) {
        let url = conversationURL(userID: userID)
        try? FileManager.default.removeItem(at: url)
    }

    private static func conversationURL(
        userID: UUID
    ) -> URL {
        let language =
            ATHLTHLocalization.isNorwegian
                ? "nb"
                : "en"

        let directory =
            FileManager.default
                .urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )
                .first ??
            URL(
                fileURLWithPath:
                    NSTemporaryDirectory(),
                isDirectory: true
            )

        return directory
            .appendingPathComponent(
                "ATHLTH",
                isDirectory: true
            )
            .appendingPathComponent(
                "recovery-coach-\(userID.uuidString)-\(language).json",
                isDirectory: false
            )
    }
}

@MainActor
final class RecoveryAIService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient = SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func generate(
        _ context: RecoveryAIContext,
        authorizedUserID: UUID,
        bypassCache: Bool = false
    ) async throws -> RecoveryAIInsight {
        // View state alone cannot authorize a third-party upload.
        guard client.auth.currentUser?.id == authorizedUserID,
              RecoveryInsightAIConsentPreferences.isAuthorized(
                userID: authorizedUserID
              ) else {
            throw RecoveryInsightAIConsentError.notAuthorized
        }

        let signature =
            try Self.cacheSignature(
                for: context
            )
        let language =
            ATHLTHLocalization.isNorwegian
                ? "nb"
                : "en"

        if !bypassCache,
           let data = RecoveryInsightProtectedCache.load(
               userID: authorizedUserID,
               language: language
           ),
           let cached = try? JSONDecoder().decode(
               RecoveryAIInsightCacheEntry.self,
               from: data
           ),
           cached.signature == signature,
           Date().timeIntervalSince(cached.createdAt) <
                6 * 60 * 60 {
            ATHLTHPerformance.event(
                "RecoveryAICacheHit"
            )
            return cached.insight
        }

        ATHLTHPerformance.event(
            "RecoveryAICacheMiss"
        )

        let insight: RecoveryAIInsight =
            try await client.functions.invoke(
                "recovery-sense-v2",
                options: FunctionInvokeOptions(
                    body: RecoveryAIRequest(
                        mode: "insight",
                        context: context,
                        question: nil,
                        language:
                            ATHLTHLocalization.isNorwegian
                                ? "nb"
                                : "en",
                        history: nil,
                        shareHealthData: true
                    )
                )
            )

        // Consent may have been withdrawn during the network request.
        // Never cache or present a revoked health-based insight.
        guard client.auth.currentUser?.id == authorizedUserID,
              RecoveryInsightAIConsentPreferences.isAuthorized(
                userID: authorizedUserID
              ) else {
            throw RecoveryInsightAIConsentError.notAuthorized
        }

        if let data = try? JSONEncoder().encode(
            RecoveryAIInsightCacheEntry(
                signature: signature,
                createdAt: Date(),
                insight: insight
            )
        ) {
            RecoveryInsightProtectedCache.save(
                data,
                userID: authorizedUserID,
                language: language
            )
        }

        return insight
    }

    static func cacheSignature(
        for context: RecoveryAIContext
    ) throws -> String {
        // Passive time progression must not invalidate the six-hour cache.
        // Muscle recovery percentage/status are time-derived, so the cache
        // key keeps only muscle identity + completed load. New Health data,
        // new workouts and new check-ins still change the signature.
        let stableContext =
            RecoveryAICacheSignature(
                recoveryScore:
                    context.recoveryScore,
                recoveryState:
                    context.recoveryState,
                sleepSeconds:
                    context.sleepSeconds,
                baselineSleepSeconds:
                    context.baselineSleepSeconds,
                hrvMilliseconds:
                    context.hrvMilliseconds,
                baselineHRVMilliseconds:
                    context.baselineHRVMilliseconds,
                restingHeartRate:
                    context.restingHeartRate,
                baselineRestingHeartRate:
                    context.baselineRestingHeartRate,
                yesterdayTrainingMinutes:
                    context.yesterdayTrainingMinutes,
                acuteTrainingMinutes:
                    context.acuteTrainingMinutes,
                chronicWeeklyAverageMinutes:
                    context.chronicWeeklyAverageMinutes,
                muscles:
                    context.muscles.map {
                        RecoveryAICacheMuscle(
                            name: $0.name,
                            completedSets:
                                $0.completedSets
                        )
                    },
                checkIn:
                    context.checkIn
            )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data =
            try encoder.encode(
                stableContext
            )
        return SHA256.hash(data: data)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    func ask(
        _ question: String,
        context: RecoveryAIContext,
        history: [RecoveryCoachMessage],
        shareHealthData: Bool = false
    ) async throws -> RecoveryCoachReply {
        let requestHistory =
            history
                .suffix(16)
                .map {
                    RecoveryAIChatTurn(
                        role:
                            $0.role.rawValue,
                        content:
                            String(
                                $0.text
                                    .prefix(1800)
                            )
                    )
                }

        let response: RecoveryAIAnswer =
            try await client.functions.invoke(
                "recovery-sense-v2",
                options: FunctionInvokeOptions(
                    body: RecoveryAIRequest(
                        mode: "ask",
                        context: shareHealthData
                            ? context : .withoutHealthData,
                        question: question,
                        language:
                            ATHLTHLocalization.isNorwegian
                                ? "nb"
                                : "en",
                        history:
                            shareHealthData && !requestHistory.isEmpty
                                ? requestHistory
                                : nil,
                        shareHealthData: shareHealthData
                    )
                )
            )

        return RecoveryCoachReply(
            answer: response.answer,
            quickQuestions:
                Array(
                    (
                        response.quickQuestions ??
                        []
                    )
                    .filter {
                        !$0
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    }
                    .prefix(3)
                )
        )
    }
}
