import Supabase
import SwiftUI

private struct AdminAIQuotaSnapshot:
    Codable,
    Hashable,
    Identifiable
{
    var id: String { provider + ":" + model }

    let provider: String
    let model: String
    let limitRequests: Int?
    let remainingRequests: Int?
    let resetRequests: String?
    let lastFeature: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case limitRequests = "limit_requests"
        case remainingRequests = "remaining_requests"
        case resetRequests = "reset_requests"
        case lastFeature = "last_feature"
        case updatedAt = "updated_at"
    }
}

@MainActor
private final class AdminAIUsageStore:
    ObservableObject
{
    @Published var snapshots:
        [AdminAIQuotaSnapshot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            snapshots =
                try await client
                    .from(
                        "ai_provider_quota_snapshots"
                    )
                    .select()
                    .order(
                        "updated_at",
                        ascending: false
                    )
                    .execute()
                    .value
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminAIUsageView: View {
    @EnvironmentObject private var session:
        AppSessionStore
    @StateObject private var store =
        AdminAIUsageStore()

    var body: some View {
        Group {
            if session.currentRole
                .canAccessControlCenter {
                content
            } else {
                ContentUnavailableView(
                    "Admin access required",
                    systemImage: "lock.shield.fill"
                )
            }
        }
        .navigationTitle("AI Usage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refresh()
        }
    }

    private var content: some View {
        List {
            Section {
                Label(
                    "Live provider quota",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                .font(.headline)

                Text(
                    "ATHLTH reads the request allowance reported by Groq after AI calls. This is the actual project/organization limit, not a hard-coded Free-plan estimate."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if store.snapshots.isEmpty {
                Section("Quota") {
                    if store.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        ContentUnavailableView(
                            "No AI quota sample yet",
                            systemImage: "sparkles",
                            description: Text(
                                "Use an ATHLTH AI feature once. The next Groq response will populate the live quota here."
                            )
                        )
                    }
                }
            } else {
                ForEach(store.snapshots) {
                    snapshot in
                    quotaSection(snapshot)
                }
            }

            Section("Prompt-saving behavior") {
                Label(
                    "Workout Insight reuses a cached answer while the workout data is unchanged.",
                    systemImage: "checkmark.circle.fill"
                )

                Label(
                    "Recovery reuses the same AI insight for unchanged recovery data for up to 6 hours.",
                    systemImage: "checkmark.circle.fill"
                )

                Label(
                    "Pull to refresh in Recovery still forces a fresh AI interpretation.",
                    systemImage: "arrow.clockwise.circle.fill"
                )

                Label(
                    "Training-plan generation and Coach questions remain user initiated and are not artificially blocked.",
                    systemImage: "hand.tap.fill"
                )
            }
            .font(.subheadline)

            if let errorMessage =
                store.errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .refreshable {
            await store.refresh()
        }
    }

    @ViewBuilder
    private func quotaSection(
        _ snapshot: AdminAIQuotaSnapshot
    ) -> some View {
        Section(
            snapshot.provider.uppercased()
        ) {
            let remaining =
                snapshot.remainingRequests
            let limit = snapshot.limitRequests

            LabeledContent(
                "Prompts remaining",
                value:
                    remaining.map(String.init)
                    ?? "—"
            )

            LabeledContent(
                "Daily request limit",
                value:
                    limit.map(String.init)
                    ?? "—"
            )

            if let remaining,
               let limit,
               limit > 0 {
                ProgressView(
                    value:
                        Double(
                            max(
                                0,
                                min(remaining, limit)
                            )
                        ),
                    total: Double(limit)
                )

                Text(
                    ATHLTHLocalization.format(
                            english: "%d%% of reported daily requests remain.",
                            norwegian: "%d %% av rapporterte daglige forespørsler gjenstår.",
                            Int(
                                (Double(remaining) /
                                 Double(limit) * 100)
                                    .rounded()
                            )
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LabeledContent(
                "Model",
                value: snapshot.model
            )

            if let reset =
                snapshot.resetRequests,
               !reset.isEmpty {
                LabeledContent(
                    "Resets in",
                    value: reset
                )
            }

            if let feature =
                snapshot.lastFeature,
               !feature.isEmpty {
                LabeledContent(
                    "Last AI feature",
                    value: feature
                )
            }

            LabeledContent(
                "Last updated",
                value:
                    snapshot.updatedAt
                        .formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
            )
        }
    }
}
