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
    @State private var directorySort: DirectorySort = .joinedNewest
    @State private var selectedAction: DirectoryAction?
    @State private var actionReason = ""
    @State private var confirmUsername = ""
    @State private var actionError: String?
    @State private var isChangingAccount = false
    private let pageSize = 50

    private enum DirectorySort: String, CaseIterable, Identifiable {
        case joinedNewest = "joined_newest"
        case joinedOldest = "joined_oldest"
        case name
        case role
        case subscription
        case status

        var id: String { rawValue }

        var title: String {
            switch self {
            case .joinedNewest: ATHLTHLocalization.choose(english: "Newest first", norwegian: "Nyeste først")
            case .joinedOldest: ATHLTHLocalization.choose(english: "Oldest first", norwegian: "Eldste først")
            case .name: ATHLTHLocalization.choose(english: "Name", norwegian: "Navn")
            case .role: ATHLTHLocalization.choose(english: "Role / title", norwegian: "Rolle / tittel")
            case .subscription: ATHLTHLocalization.choose(english: "Subscription", norwegian: "Abonnement")
            case .status: ATHLTHLocalization.choose(english: "Account status", norwegian: "Kontostatus")
            }
        }
    }

    private struct DirectoryAction: Identifiable {
        enum Kind: String {
            case promote, demote, suspend, restore, requestDeletion
        }
        let user: DirectoryUser
        let kind: Kind
        var id: String { user.userID.uuidString + "-" + kind.rawValue }

        var isRoleChange: Bool { kind == .promote || kind == .demote }
        var title: String {
            switch kind {
            case .promote: return ATHLTHLocalization.choose(
                english: "Grant administrator access", norwegian: "Forfrem til administrator")
            case .demote: return ATHLTHLocalization.choose(
                english: "Remove administrator access", norwegian: "Fjern administratortilgang")
            case .suspend: return ATHLTHLocalization.choose(
                english: "Deactivate account", norwegian: "Deaktiver konto")
            case .restore: return ATHLTHLocalization.choose(
                english: "Reactivate account", norwegian: "Aktiver konto")
            case .requestDeletion: return ATHLTHLocalization.choose(
                english: "Request deletion review", norwegian: "Be om sletting")
            }
        }
    }

    private struct Query: Encodable {
        let p_search: String
        let p_sort: String
        let p_limit: Int
        let p_offset: Int
    }

    private struct DirectoryUser: Decodable, Identifiable {
        let userID: UUID
        let username: String?
        let displayName: String?
        let avatarURL: String?
        let accountRole: String
        let subscriptionTier: String
        let subscriptionStatus: String
        let accountState: String
        let joinedAt: Date
        let totalCount: Int

        var id: UUID { userID }

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case username
            case displayName = "display_name"
            case avatarURL = "avatar_url"
            case accountRole = "account_role"
            case subscriptionTier = "subscription_tier"
            case subscriptionStatus = "subscription_status"
            case accountState = "account_state"
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

                    Menu {
                        Picker(tr("Sort by", "Sorter etter"), selection: $directorySort) {
                            ForEach(DirectorySort.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label(directorySort.title, systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                    }
                    .accessibilityIdentifier("admin-directory-sort")

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
        .onChange(of: directorySort) { _, _ in
            offset = 0
            Task { await loadPage() }
        }
        .sheet(item: $selectedAction) { action in
            accountActionSheet(action)
        }
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
                userAvatar(user)
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

                if session.currentRole.canManageAdmins &&
                   user.userID != session.profile.userID &&
                   user.accountRole.lowercased() != "owner" {
                    Menu {
                        if user.accountRole.lowercased() == "admin" {
                            Button {
                                prepare(.demote, user: user)
                            } label: {
                                Label(tr("Remove admin", "Fjern administrator"),
                                      systemImage: "person.badge.minus")
                            }
                        } else {
                            Button {
                                prepare(.promote, user: user)
                            } label: {
                                Label(tr("Promote to admin", "Forfrem til administrator"),
                                      systemImage: "person.badge.key.fill")
                            }
                        }
                        Divider()
                        if user.accountState == "suspended" {
                            Button {
                                prepare(.restore, user: user)
                            } label: {
                                Label(tr("Reactivate", "Aktiver"),
                                      systemImage: "checkmark.shield")
                            }
                        } else {
                            Button {
                                prepare(.suspend, user: user)
                            } label: {
                                Label(tr("Deactivate", "Deaktiver"),
                                      systemImage: "person.crop.circle.badge.xmark")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            prepare(.requestDeletion, user: user)
                        } label: {
                            Label(tr("Request deletion", "Be om sletting"),
                                  systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(gold)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(tr("Manage account", "Administrer konto"))
                }
            }

            Rectangle()
                .fill(outline.opacity(0.35))
                .frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) {
                    subscriptionDetail(user, plan: plan)
                    registeredDetail(user)
                    accountStatusDetail(user)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 13) {
                    subscriptionDetail(user, plan: plan)
                    registeredDetail(user)
                    accountStatusDetail(user)
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
                ATHLTHAdminDirectoryPresentation.subscriptionLabel(
                    tier: user.subscriptionTier,
                    status: user.subscriptionStatus,
                    norwegian: norwegian
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

    @ViewBuilder
    private func userAvatar(_ user: DirectoryUser) -> some View {
        let url = user.avatarURL.flatMap(URL.init(string:))
        let trustedURL = url?.scheme?.lowercased() == "https" ? url : nil
        AsyncImage(url: trustedURL, transaction: Transaction(animation: .easeInOut(duration: 0.18))) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Text(ATHLTHAdminDirectoryPresentation.initials(
                    user.displayName, username: user.username
                ))
                .font(.subheadline.bold())
                .foregroundStyle(gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(canvas)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(outline.opacity(0.4), lineWidth: 1))
    }

    private func accountStatusDetail(_ user: DirectoryUser) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("ACCOUNT STATUS", "KONTOSTATUS"))
                .font(.caption2.weight(.medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Label(
                ATHLTHAdminDirectoryPresentation.accountStatusTitle(
                    user.accountState, norwegian: norwegian
                ),
                systemImage: user.accountState == "suspended"
                    ? "person.crop.circle.badge.xmark" : "checkmark.shield"
            )
            .font(.subheadline)
            .foregroundStyle(user.accountState == "suspended" ? .red : ink)
        }
    }

    private func prepare(_ kind: DirectoryAction.Kind, user: DirectoryUser) {
        guard session.currentRole.canManageAdmins,
              user.userID != session.profile.userID,
              user.accountRole.lowercased() != "owner" else { return }
        actionReason = ""
        confirmUsername = ""
        actionError = nil
        selectedAction = DirectoryAction(user: user, kind: kind)
    }

    private struct RoleChangeRequest: Encodable {
        let p_target: UUID
        let p_role: String
        let p_reason: String
    }

    private struct AccountSupportRequest: Encodable {
        let action: String
        let user_id: String
        let confirm_username: String
        let reason: String
    }

    private struct AccountSupportResponse: Decodable {
        let success: Bool?
        let requested: Bool?
    }

    private func accountActionSheet(_ action: DirectoryAction) -> some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(tr("Account", "Konto")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ATHLTHAdminDirectoryPresentation.displayName(
                                action.user.displayName, username: action.user.username
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text("@\(action.user.username ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(action.title)
                        .font(.headline)
                } footer: {
                    Text(tr(
                        "Only the owner can change access. The action is recorded for security auditing. No health information or messages are accessed.",
                        "Bare eier kan endre tilgangen. Handlingen loggføres av sikkerhetshensyn. Helseopplysninger og meldinger åpnes ikke."
                    ))
                }

                Section(tr("Why is this needed?", "Hvorfor er dette nødvendig?")) {
                    TextField(
                        tr("Reason for the change (required)", "Begrunnelse (obligatorisk)"),
                        text: $actionReason, axis: .vertical
                    )
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.sentences)

                    TextField(
                        tr("Confirm exact username", "Bekreft brukernavn"),
                        text: $confirmUsername
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("admin-confirm-username")
                }

                if action.kind == .requestDeletion {
                    Section {
                        Label(
                            tr(
                                "This requests a deletion review. It does not immediately delete the account.",
                                "Dette oppretter en sletteforespørsel. Kontoen slettes ikke umiddelbart."
                            ),
                            systemImage: "lock.shield"
                        )
                        .font(.subheadline)
                    }
                } else if action.kind == .suspend {
                    Section {
                        Text(tr(
                            "Suspension prevents new sign-ins and token renewal. Existing sessions may remain valid until their current access token expires.",
                            "Deaktivering hindrer ny innlogging og fornyelse av token. Eksisterende tilgang kan vare frem til tokenet utløper."
                        ))
                        .font(.caption)
                    }
                }

                if let actionError {
                    Section {
                        Label(actionError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { selectedAction = nil }
                        .disabled(isChangingAccount)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Confirm", "Bekreft")) {
                        Task { await perform(action) }
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        isChangingAccount ||
                        actionReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 ||
                        confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased() != (action.user.username ?? "").lowercased()
                    )
                }
            }
            .interactiveDismissDisabled(isChangingAccount)
        }
    }

    @MainActor
    private func perform(_ action: DirectoryAction) async {
        guard session.currentRole.canManageAdmins,
              action.user.accountRole.lowercased() != "owner",
              action.user.userID != session.profile.userID,
              !isChangingAccount else { return }
        isChangingAccount = true
        actionError = nil
        defer { isChangingAccount = false }

        do {
            if action.isRoleChange {
                let role = action.kind == .promote ? "admin" : "user"
                let changed: Bool = try await SupabaseEnvironment.client
                    .rpc("athlth_admin_change_role", params: RoleChangeRequest(
                        p_target: action.user.userID,
                        p_role: role,
                        p_reason: actionReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    .execute().value
                guard changed else { throw DirectoryActionError.failed }
            } else {
                let operation: String
                switch action.kind {
                case .suspend: operation = "suspend"
                case .restore: operation = "restore"
                case .requestDeletion: operation = "request_deletion"
                default: throw DirectoryActionError.failed
                }
                let response: AccountSupportResponse = try await SupabaseEnvironment.client.functions
                    .invoke("admin-account-support", options: FunctionInvokeOptions(
                        body: AccountSupportRequest(
                            action: operation,
                            user_id: action.user.userID.uuidString.lowercased(),
                            confirm_username: confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                            reason: actionReason.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    ))
                guard response.success == true || response.requested == true else {
                    throw DirectoryActionError.failed
                }
            }
            selectedAction = nil
            await loadPage()
        } catch {
            actionError = tr(
                "Could not complete account change. Verify permissions and retry.",
                "Kunne ikke gjennomføre kontoendringen. Kontroller tillatelsene og prøv igjen."
            )
        }
    }

    private enum DirectoryActionError: Error {
        case failed
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
                .rpc("athlth_admin_directory_v2", params: Query(
                    p_search: submittedSearch,
                    p_sort: directorySort.rawValue,
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
