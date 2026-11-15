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

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let outline = ATHLTHStudioStyle.outline
    private let canvas = ATHLTHStudioStyle.canvas

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var norwegian: Bool { ATHLTHLocalization.isNorwegian }

    private var totalUsers: Int { users.first?.totalCount ?? 0 }

    private var directory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(tr("Users", "Brukere"))
                        .font(.title3.bold())
                        .foregroundStyle(ink)

                    if !isLoading {
                        Text(totalUsers.formatted())
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(gold)
                    }

                    Spacer(minLength: 0)

                    if isLoading { ProgressView() }
                }

                if let failure {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(ink)
                        Button(tr("Try again", "Prøv igjen")) {
                            Task { await loadPage() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }

                if users.isEmpty && isLoading {
                    ProgressView(tr("Loading accounts", "Henter brukerkontoer"))
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if users.isEmpty && failure == nil {
                    if submittedSearch.isEmpty {
                        ContentUnavailableView(
                            tr("No accounts found", "Ingen brukerkontoer funnet"),
                            systemImage: "person.3",
                            description: Text(tr(
                                "No account records are available.",
                                "Ingen registrerte brukerkontoer er tilgjengelige."
                            ))
                        )
                    } else {
                        ContentUnavailableView.search(text: submittedSearch)
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(users) { user in
                            accountCard(user)
                        }
                    }
                }

                if totalUsers > pageSize || offset > 0 {
                    pageControls
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(canvas.ignoresSafeArea())
        .searchable(
            text: $searchText,
            prompt: tr("Search by name or username", "Søk på navn eller brukernavn")
        )
        .onSubmit(of: .search) {
            submittedSearch = String(searchText.prefix(80))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            offset = 0
            Task { await loadPage() }
        }
        .refreshable { await loadPage() }
        .accessibilityIdentifier("athlth-admin-user-directory")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.title3)
                    .foregroundStyle(gold)
                    .frame(width: 44, height: 44)
                    .background(canvas, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Account directory", "Brukerkontoer"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)

                    Text(tr(
                        "Account details and subscription types",
                        "Oversikt over kontoer og abonnementstyper"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Label(
                tr(
                    "Read-only. Health information, messages and private workouts are not shown.",
                    "Kun lesetilgang. Helseopplysninger, meldinger og private treningsøkter vises ikke."
                ),
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(outline.opacity(0.55), lineWidth: 1)
        }
    }

    private func accountCard(_ user: DirectoryUser) -> some View {
        let name = ATHLTHAdminDirectoryPresentation.displayName(
            user.displayName, username: user.username
        )
        let plan = ATHLTHAdminDirectoryPresentation.plan(for: user.subscriptionTier)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 13) {
                Text(ATHLTHAdminDirectoryPresentation.initials(
                    user.displayName, username: user.username
                ))
                .font(.subheadline.bold())
                .foregroundStyle(gold)
                .frame(width: 46, height: 46)
                .background(canvas, in: Circle())
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(ink)
                        .lineLimit(2)

                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(ATHLTHAdminDirectoryPresentation.roleTitle(
                    user.accountRole, norwegian: norwegian
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(user.accountRole.lowercased() == "user" ? ink : gold)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    canvas,
                    in: Capsule()
                )
                .accessibilityLabel(
                    "\(tr("Access role", "Tilgangsrolle")): " +
                    ATHLTHAdminDirectoryPresentation.roleTitle(
                        user.accountRole, norwegian: norwegian
                    )
                )
            }

            Rectangle()
                .fill(outline.opacity(0.35))
                .frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) {
                    subscriptionDetail(user, plan: plan)
                    registeredDetail(user)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 13) {
                    subscriptionDetail(user, plan: plan)
                    registeredDetail(user)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(outline.opacity(0.48), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func subscriptionDetail(
        _ user: DirectoryUser,
        plan: ATHLTHAdminDirectoryPresentation.Plan
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("SUBSCRIPTION TYPE", "ABONNEMENTSTYPE"))
                .font(.caption2.weight(.medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Label(
                ATHLTHAdminDirectoryPresentation.planTitle(
                    user.subscriptionTier, norwegian: norwegian
                ),
                systemImage: plan == .plus ? "sparkles" : "person.crop.circle"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(plan == .plus ? gold : ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func registeredDetail(_ user: DirectoryUser) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("REGISTERED", "REGISTRERT"))
                .font(.caption2.weight(.medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Label(
                user.joinedAt.formatted(date: .abbreviated, time: .omitted),
                systemImage: "calendar"
            )
            .font(.subheadline)
            .foregroundStyle(ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var pageControls: some View {
        HStack(spacing: 12) {
            Button {
                offset = max(0, offset - pageSize)
                Task { await loadPage() }
            } label: {
                Label(tr("Previous", "Forrige"), systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .disabled(offset == 0 || isLoading)

            Spacer(minLength: 0)

            Text(tr(
                "\(offset + (users.isEmpty ? 0 : 1))–\(offset + users.count) of \(totalUsers)",
                "\(offset + (users.isEmpty ? 0 : 1))–\(offset + users.count) av \(totalUsers)"
            ))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                offset += pageSize
                Task { await loadPage() }
            } label: {
                Label(tr("Next", "Neste"), systemImage: "chevron.right")
                    .frame(minHeight: 44)
            }
            .disabled(isLoading || offset + users.count >= totalUsers)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ink)
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
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
