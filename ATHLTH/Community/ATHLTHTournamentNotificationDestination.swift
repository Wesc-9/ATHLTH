import SwiftUI

/// Opens a specific tournament chat after an Inbox notification or APNs tap.
/// Only existing tournament members can resolve the protected server row.
struct ATHLTHTournamentNotificationDestination: View {
    let tournamentID: UUID

    @State private var tournament: ATHLTHTournamentRemote?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let tournament {
                ATHLTHTournamentGroupConversationView(tournament: tournament)
            } else if loading {
                ProgressView("Åpner konkurransesamtalen…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ContentUnavailableView(
                    "Konkurransen er ikke tilgjengelig",
                    systemImage: "trophy",
                    description: Text(errorMessage ??
                        "Du har kanskje ikke lenger tilgang til konkurransen.")
                )
            }
        }
        .task(id: tournamentID) {
            loading = true
            defer { loading = false }
            do {
                tournament = try await ATHLTHTournamentCloudService()
                    .visibleTournaments()
                    .first { $0.id == tournamentID }
                if tournament == nil {
                    errorMessage = "Fant ikke en tilgjengelig konkurranse."
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
