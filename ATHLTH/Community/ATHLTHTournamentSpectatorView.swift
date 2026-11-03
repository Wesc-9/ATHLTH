import SwiftUI
import Supabase

/// Only the explicit public-results RPC is used here. The spectator view
/// never fetches the private lobby, invitations, workout proofs or chat.
struct ATHLTHTournamentPublicListing: Decodable, Identifiable {
    let id: UUID
    let title: String
    let format: String
    let status: String
    let participantCount: Int
    enum CodingKeys: String, CodingKey {
        case id, title, format, status
        case participantCount = "participant_count"
    }
}

struct ATHLTHTournamentPublicStanding: Decodable, Identifiable {
    let username: String
    let group: Int?
    let rank: Int
    let points: Int
    let difference: Double
    let played: Int
    let wins: Int
    var id: String { "\(group ?? -1):\(rank):\(username)" }
}

struct ATHLTHTournamentPublicMatch: Decodable, Identifiable {
    let phase: String
    let round: Int
    let group: Int?
    let slot: Int
    let status: String
    let home: String
    let away: String
    let homeScore: Double?
    let awayScore: Double?
    var id: String { "\(phase):\(group ?? -1):\(round):\(slot)" }
    enum CodingKeys: String, CodingKey {
        case phase, round, group, slot, status, home, away
        case homeScore = "home_score"
        case awayScore = "away_score"
    }
}

struct ATHLTHTournamentPublicResults: Decodable {
    let id: UUID
    let title: String
    let format: String
    let status: String
    let standings: [ATHLTHTournamentPublicStanding]
    let matches: [ATHLTHTournamentPublicMatch]
}

private struct ATHLTHTournamentPublicResultParams: Encodable {
    let p_tournament: UUID
}

struct ATHLTHTournamentPublicDirectoryView: View {
    @State private var competitions: [ATHLTHTournamentPublicListing] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Offentlige konkurranser")
                    .font(.system(size: 29,weight: .regular,design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                Text("Se tabeller, cuptrær og godkjente resultater. Deltakernes private meldinger og treningsdokumentasjon er ikke tilgjengelige.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                if loading { ProgressView("Henter konkurranser…") }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if !loading && competitions.isEmpty {
                    ContentUnavailableView("Ingen offentlige turneringer",
                        systemImage: "trophy",
                        description: Text("Turneringer vises her når arrangøren og deltakerne har godkjent offentlig resultatvisning."))
                }
                ForEach(competitions) { competition in
                    NavigationLink {
                        ATHLTHTournamentSpectatorDetailView(id: competition.id)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: competition.format == "cup"
                                  ? "trophy" : "chart.bar.xaxis")
                                .font(.title3.weight(.ultraLight))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                                .frame(width: 34)
                            VStack(alignment: .leading,spacing: 4) {
                                Text(competition.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                                Text("\(competition.participantCount) deltakere · " +
                                     (competition.status == "completed" ? "Fullført" : "Pågår"))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        .padding(15)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .navigationTitle("Utforsk")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor private func refresh() async {
        loading=true
        defer { loading=false }
        do {
            let result: [ATHLTHTournamentPublicListing] = try await
                SupabaseEnvironment.client.rpc(
                    "athlth_tournament_public_discover"
                ).execute().value
            competitions=result
            error=nil
        } catch {
            error=error.localizedDescription
        }
    }
}

struct ATHLTHTournamentSpectatorDetailView: View {
    let id: UUID
    @State private var results: ATHLTHTournamentPublicResults?
    @State private var loading=true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 18) {
                if loading { ProgressView("Henter resultater…") }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if let results {
                    Text(results.title)
                        .font(.system(size: 29,weight: .regular,design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Label("Kun offentlig resultatvisning",
                          systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    if !results.standings.isEmpty {
                        Text("Tabell")
                            .font(.system(size: 22,design: .serif))
                        VStack(spacing: 8) {
                            ForEach(results.standings) { row in
                                HStack(spacing: 8) {
                                    Text("\(row.rank)")
                                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                                        .frame(width: 24,alignment: .leading)
                                    Text(row.username)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(row.played) K")
                                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                                    Text("\(row.points) P")
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                                if row.id != results.standings.last?.id {
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                        .padding(15)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                    Text("Oppgjør og cup")
                        .font(.system(size: 22,design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    ForEach(results.matches) { match in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading,spacing: 5) {
                                Text("Runde \(match.round)" +
                                     (match.group.map { " · Gruppe \($0 + 1)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                                Text(match.home + " vs " + match.away)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                            }
                            Spacer()
                            if match.status == "confirmed",
                               let home=match.homeScore,
                               let away=match.awayScore {
                                Text(String(format:"%.0f–%.0f",home,away))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                            } else {
                                Text("Ikke avgjort")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                        }
                        .padding(14)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                }
            }
            .padding(18)
        }
        .background(ATHLTHArenaV3Style.cream.ignoresSafeArea())
        .navigationTitle("Resultater")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor private func refresh() async {
        loading=true
        defer { loading=false }
        do {
            let result: ATHLTHTournamentPublicResults = try await
                SupabaseEnvironment.client.rpc(
                    "athlth_tournament_public_results",
                    params: ATHLTHTournamentPublicResultParams(p_tournament: id)
                ).execute().value
            results=result
            error=nil
        } catch {
            error=error.localizedDescription
        }
    }
}
