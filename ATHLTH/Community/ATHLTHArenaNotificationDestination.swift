import SwiftUI

/// Resolved directly by series ID so social inbox and push notifications
/// take the athlete to the exact competition, not the generic Community tab.
struct ATHLTHArenaNotificationDestination: View {
    let seriesID: UUID
    @State private var series: ATHLTHArenaRemoteSeries?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if let series {
                ATHLTHArenaOnlineDetailView(series: series)
            } else if loading {
                ProgressView(
                    ATHLTHLocalization.choose(
                        english: "Opening Arena...",
                        norwegian: "Åpner Arena..."
                    )
                )
            } else {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "Competition unavailable",
                        norwegian: "Konkurransen er ikke tilgjengelig"
                    ),
                    systemImage: "trophy",
                    description: Text(error ?? ATHLTHLocalization.choose(
                        english: "You may no longer have access to this series.",
                        norwegian: "Du har kanskje ikke lenger tilgang til denne serien."
                    ))
                )
            }
        }
        .task(id: seriesID) {
            loading = true
            defer { loading = false }
            do {
                series = try await ATHLTHArenaCloudService().loadSeries()
                    .first { $0.id == seriesID }
                if series == nil {
                    error = ATHLTHLocalization.choose(
                        english: "This invitation is no longer available.",
                        norwegian: "Denne invitasjonen er ikke lenger tilgjengelig."
                    )
                }
            } catch {
                error = error.localizedDescription
            }
        }
    }
}
