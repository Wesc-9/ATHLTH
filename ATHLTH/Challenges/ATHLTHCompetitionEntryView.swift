import SwiftUI

/// Stable entry point for competition creation outside a specific Quick
/// Train mode (friends, community, Arena). No legacy Challenge editor is
/// mounted while opening this view, avoiding its large nested sheet graph.
struct ATHLTHCompetitionEntryView: View {
    @Environment(\.dismiss) private var dismiss

    var preselectedFriend: SocialProfileCard? = nil
    var initialFormat: ATHLTHCompetitionFormat? = nil

    @State private var selectedActivity: ATHLTHQuickStartActivity = .running
    @State private var showingCreator = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose sport", norwegian: "Velg treningsform"
                    ))
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(ATHLTHLocalization.choose(
                        english: "Duel, league and cup all use the same competition rules and workout results.",
                        norwegian: "Duell, liga og cup bruker samme konkurranseregler og treningsresultater."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    ForEach(
                        [ATHLTHQuickStartActivity.running, .walking, .strength],
                        id: \.self
                    ) { activity in
                        Button {
                            selectedActivity = activity
                            showingCreator = true
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: activity.symbol)
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .frame(width: 50, height: 50)
                                    .background(ATHLTHPlanDesign.selectedSurface,
                                                in: RoundedRectangle(cornerRadius: 15))
                                Text(activity.title)
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                            .padding(15)
                            .background(Color.white,
                                        in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(ATHLTHPlanDesign.outline,
                                                  lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "athlth-competition-entry-\(activity.title)"
                        )
                    }
                }
                .frame(maxWidth: 620)
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Competition", norwegian: "Konkurranse"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreator) {
                // Only instantiate the heavy editor AFTER the athlete
                // chooses a sport. Erasure prevents generic type metadata
                // expansion across the nested competition sheet boundary.
                AnyView(ATHLTHCompetitionCreationView(
                    initialActivity: selectedActivity,
                    advanced: true,
                    initialFormat: initialFormat,
                    preselectedFriend: preselectedFriend
                ))
            }
        }
        .presentationDetents([.large])
    }
}
