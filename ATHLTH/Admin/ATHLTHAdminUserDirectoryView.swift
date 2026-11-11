import SwiftUI
import Supabase

/// Only backend-verified administrators can read the directory.
/// The database function rechecks the authenticated JWT account role for
/// every request; this client-side gate is merely a navigation convenience.
struct ATHLTHAdminUserDirectoryView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var searchText = ""
    @State private var submittedSearch = ""
    @State private var users: [DirectoryUser] = []
    @State private var offset = 0
    @State private var isLoading = false
    @State private var failure: String?
    private let pageSize = 50

    private struct Query: Encodable {
        let p_search: String
        let p_limit: Int
        let p_offset: Int
    }

    private struct DirectoryUser: Decodable, Identifiable {
        let userID: UUID
        let username: String?
        let displayName: String?
        let accountRole: String
        let subscriptionTier: String
        let joinedAt: Date
        let totalCount: Int

        var id: UUID { userID }

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case username
            case displayName = "display_name"
            case accountRole = "account_role"
            case subscriptionTier = "subscription_tier"
            case joinedAt = "joined_at"
            case totalCount = "total_count"
        }
    }

    var body: some View {
        Group {
            if session.currentRole.canAccessControlCenter {
                directory
            } else {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "Admin access required",
                        norwegian: "Krever administratortilgang"
                    ),
                    systemImage: "lock.shield"
                )
            }
        }
        .navigationTitle(ATHLTHLocalization.choose(
            english: "User directory", norwegian: "Brukeroversikt"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPage() }
    }

    private var directory: some View {
        List {
            Section {
                HStack {
                    Label(ATHLTHLocalization.choose(
                        english: "Account records", norwegian: "Brukerkontoer"
                    ), systemImage: "person.3")
                    Spacer()
                    if isLoading { ProgressView() }
                }
                .font(.subheadline.weight(.semibold))

                Text(ATHLTHLocalization.choose(
                    english: "Read-only: display name, username, access role, plan and joining date. Health, messages and private workout data are not exposed.",
                    norwegian: "Kun lesetilgang: visningsnavn, brukernavn, tilgangsrolle, abonnement og registreringsdato. Helsedata, meldinger og private økter vises ikke."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button(ATHLTHLocalization.choose(
                        english: "Try again", norwegian: "Prøv igjen"
                    )) {
                        Task { await loadPage() }
                    }
                }
            }

            Section(ATHLTHLocalization.choose(
                english: "Users", norwegian: "Brukere"
            )) {
                ForEach(users) { user in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(user.displayName?.isEmpty == false
                                ? user.displayName!
                                : (user.username ?? "—"))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 10)
                            Text(user.accountRole.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                        }
                        if let username = user.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Label(user.subscriptionTier, systemImage: "checkmark.seal")
                            Label(user.joinedAt.formatted(date: .abbreviated, time: .omitted),
                                  systemImage: "calendar")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
                if users.isEmpty && !isLoading && failure == nil {
                    ContentUnavailableView.search(text: submittedSearch)
                }
            }

            Section {
                HStack(spacing: 15) {
                    Button {
                        offset = max(0, offset - pageSize)
                        Task { await loadPage() }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Previous", norwegian: "Forrige"
                        ), systemImage: "chevron.left")
                    }
                    .disabled(offset == 0 || isLoading)

                    Spacer()

                    Text("\(offset + (users.isEmpty ? 0 : 1))–\(offset + users.count) / \(users.first?.totalCount ?? 0)")
                        .font(.caption.monospacedDigit())

                    Spacer()

                    Button {
                        offset += pageSize
                        Task { await loadPage() }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Next", norwegian: "Neste"
                        ), systemImage: "chevron.right")
                    }
                    .disabled(isLoading || offset + users.count >= (users.first?.totalCount ?? 0))
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: ATHLTHLocalization.choose(
            english: "Find username or name", norwegian: "Søk etter brukernavn eller navn"
        ))
        .onSubmit(of: .search) {
            submittedSearch = String(searchText.prefix(80))
            offset = 0
            Task { await loadPage() }
        }
        .refreshable { await loadPage() }
    }

    @MainActor
    private func loadPage() async {
        guard session.currentRole.canAccessControlCenter,
              SupabaseEnvironment.client.auth.currentUser?.id == session.profile.userID
        else {
            users = []
            return
        }
        guard !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let result: [DirectoryUser] = try await SupabaseEnvironment.client
                .rpc("athlth_admin_directory", params: Query(
                    p_search: submittedSearch,
                    p_limit: pageSize,
                    p_offset: offset
                ))
                .execute()
                .value
            users = result
        } catch {
            users = []
            failure = ATHLTHLocalization.choose(
                english: "Could not retrieve the authorized user directory. Check the account role and network.",
                norwegian: "Kunne ikke hente brukeroversikten. Kontroller tilgangsrollen og nettverket."
            )
        }
    }
}
