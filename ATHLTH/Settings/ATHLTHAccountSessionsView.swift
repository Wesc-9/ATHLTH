import SwiftUI
import UIKit

struct ATHLTHAccountSession: Decodable, Identifiable {
    let sessionID: UUID
    let deviceKind: String
    let signedInAt: Date
    let lastRefreshedAt: Date?
    let isCurrent: Bool
    let isActive: Bool
    var id: UUID { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case deviceKind = "device_kind"
        case signedInAt = "signed_in_at"
        case lastRefreshedAt = "last_refreshed_at"
        case isCurrent = "is_current"
        case isActive = "is_active"
    }

    static var currentDeviceKind: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }
}

struct ATHLTHAccountSessionsView: View {
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var session: AppSessionStore
    @State private var entries: [ATHLTHAccountSession] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var selected: ATHLTHAccountSession?
    @State private var revoking = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(tr("Signed-in devices", "Innloggede enheter"))
                    .font(.system(size: 32, design: .serif))
                Text(tr("Manage your account sessions. Last activity refers to token refresh, not live presence.", "Administrer innloggingene dine. Sist oppdatert gjelder fornyelse av innloggingen, ikke om enheten er i bruk nå."))
                    .font(.subheadline).foregroundStyle(ATHLTHTheme.mutedText)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
                section(tr("Active sessions", "Aktive innlogginger"), items: entries.filter(\.isActive))
                section(tr("Login history · last 90 days", "Innloggingshistorikk · siste 90 dager"), items: entries.filter { !$0.isActive })
                Text(tr("Older sessions may have an unknown device type. History starts when the device first registers with this version.", "Eldre innlogginger kan ha ukjent enhetstype. Historikken registreres fra første gang enheten bruker denne versjonen."))
                    .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                Text(tr("Revoked sessions may retain access until their current access token expires.", "Tilbakekalte innlogginger kan ha tilgang frem til gjeldende tilgangstoken utløper."))
                    .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(18).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
        .navigationTitle(tr("Devices", "Enheter"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading || revoking)
            }
        }
        .task(id: session.profile.userID) { entries = []; await load() }
        .confirmationDialog(tr("Revoke access?", "Trekk tilbake tilgang?"), isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }
        ), titleVisibility: .visible) {
            Button(tr("Revoke access", "Trekk tilbake tilgang"), role: .destructive) {
                guard let item = selected else { return }
                selected = nil
                Task { await revoke(item) }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) { selected = nil }
        }
    }

    private func section(_ title: String, items: [ATHLTHAccountSession]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.8)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            PremiumSettingsCard {
                if items.isEmpty {
                    Text(tr("No sessions recorded", "Ingen innlogginger registrert"))
                        .font(.subheadline).foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                ForEach(items.sorted { $0.signedInAt > $1.signedInAt }) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        PremiumSettingsRow(
                            icon: item.deviceKind == "iPad" ? "ipad" : item.deviceKind == "iPhone" ? "iphone" : "desktopcomputer",
                            iconTint: ATHLTHTheme.accentDeep, iconBackground: ATHLTHTheme.premiumGoldSoft,
                            title: item.deviceKind == "Other" ? tr("Unknown device", "Ukjent enhet") : item.deviceKind,
                            subtitle: tr("Signed in", "Innlogget") + ": " + item.signedInAt.formatted(date: .abbreviated, time: .shortened)
                        ) {
                            if item.isCurrent {
                                Text(tr("This device", "Denne enheten")).font(.caption).foregroundStyle(ATHLTHTheme.accentDeep)
                            } else if item.isActive {
                                Button(role: .destructive) { selected = item } label: {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                }
                                .buttonStyle(.plain).foregroundStyle(.red).disabled(revoking)
                                .accessibilityLabel(tr("Revoke access", "Trekk tilbake tilgang"))
                            }
                        }
                        if let refreshed = item.lastRefreshedAt, item.isActive {
                            Text(tr("Last refreshed", "Sist oppdatert") + ": " + refreshed.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                                .padding(.horizontal, 16).padding(.bottom, 10)
                        }
                    }
                    if item.id != items.sorted(by: { $0.signedInAt > $1.signedInAt }).last?.id { SettingsDivider() }
                }
            }
        }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true; errorText = nil
        let owner = session.profile.userID
        defer { loading = false }
        do {
            let result = try await accountService.accountSessions(deviceKind: ATHLTHAccountSession.currentDeviceKind)
            guard owner == session.profile.userID, session.signedIn else { return }
            entries = result
        } catch {
            errorText = tr("Could not retrieve sessions.", "Kunne ikke hente innlogginger.")
        }
    }

    @MainActor private func revoke(_ item: ATHLTHAccountSession) async {
        guard !revoking, !item.isCurrent, item.isActive else { return }
        revoking = true
        defer { revoking = false }
        do {
            _ = try await accountService.revokeAccountSession(item.id)
            await load()
        } catch {
            errorText = tr("Could not revoke access.", "Kunne ikke trekke tilbake tilgang.")
        }
    }
}
