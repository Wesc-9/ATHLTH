import Supabase
import SwiftUI

private struct ActivityCenterVisualFlagRow: Decodable {
    let key: String
    let enabled: Bool
}

private struct ActivityCenterVisualFlagUpdate: Encodable {
    let enabled: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case enabled
        case updatedAt = "updated_at"
    }
}

@MainActor
final class ActivityCenterVisualSettings: ObservableObject {
    static let shared = ActivityCenterVisualSettings()

    @Published private(set) var aiWorkoutHeroEnabled = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient
    private let flagKey = "activity_center_ai_workout_hero"

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [ActivityCenterVisualFlagRow] =
                try await client
                    .from("app_feature_flags")
                    .select("key,enabled")
                    .eq("key", value: flagKey)
                    .limit(1)
                    .execute()
                    .value

            aiWorkoutHeroEnabled = rows.first?.enabled ?? false
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            aiWorkoutHeroEnabled = false
            errorMessage = error.localizedDescription
        }
    }

    func setAIWorkoutHeroEnabled(_ enabled: Bool) async {
        guard !isSaving else { return }

        let previousValue = aiWorkoutHeroEnabled
        aiWorkoutHeroEnabled = enabled
        isSaving = true
        defer { isSaving = false }

        do {
            let update = ActivityCenterVisualFlagUpdate(
                enabled: enabled,
                updatedAt: Date()
            )

            try await client
                .from("app_feature_flags")
                .update(update)
                .eq("key", value: flagKey)
                .execute()

            errorMessage = nil
        } catch {
            aiWorkoutHeroEnabled = previousValue
            errorMessage = error.localizedDescription
        }
    }
}
