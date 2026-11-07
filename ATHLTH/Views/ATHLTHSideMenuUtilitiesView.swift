import SwiftUI

/// Exact same search, message inbox and notification center destinations
/// that previously lived in the top-right Home hero toolbar.
struct ATHLTHSideMenuUtilitiesView: View {
    @Environment(\.dismiss) private var dismiss

    let destination: ATHLTHSideMenuDestination

    var body: some View {
        NavigationStack {
            destinationContent
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Inbox has its own in-content back button replacing
                    // the profile avatar. Avoid a competing Close affordance.
                    if destination != .inbox {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) {
                                dismiss()
                            }
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationCornerRadius(28)
    }

    private var title: String {
        switch destination {
        case .search:
            return ATHLTHLocalization.choose(
                english: "Search", norwegian: "Søk"
            )
        case .inbox:
            return ATHLTHLocalization.choose(
                english: "Inbox", norwegian: "Innboks"
            )
        case .notifications:
            return ATHLTHLocalization.choose(
                english: "Notifications", norwegian: "Varsler"
            )
        default:
            return "ATHLTH"
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .search:
            ATHLTHGlobalSearchView()
        case .inbox:
            MessageInboxDestinationView(onBack: { dismiss() })
        case .notifications:
            ATHLTHNotificationCenterView()
        default:
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "No destination", norwegian: "Ingen destinasjon"
                ),
                systemImage: "square.dashed"
            )
        }
    }
}
