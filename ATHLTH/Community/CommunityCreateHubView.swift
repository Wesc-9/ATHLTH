import SwiftUI

/// A single starting point for social plans. Each choice opens the existing
/// authoritative workflow: no duplicated workout planner or new storage tables.
struct ATHLTHCommunityCreateHubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ATHLTHPlanSurface {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("ATHLTH · COMMUNITY")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                            Text(ATHLTHLocalization.choose(
                                english: "What would you like to arrange?",
                                norwegian: "Hva vil du arrangere?"
                            ))
                            .font(.system(size: 28, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "Choose a goal. ATHLTH opens the right planner without making you learn different creation tools.",
                                norwegian: "Velg hva du vil gjøre. ATHLTH åpner riktig planlegging uten at du må lære flere opprettelsesverktøy."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }

                    navigationRow(
                        title: ATHLTHLocalization.choose(
                            english: "Train in person",
                            norwegian: "Trene fysisk sammen"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Shared workout with a private meeting place.",
                            norwegian: "Felles økt med privat oppmøtested."
                        ),
                        icon: "figure.run",
                        destination: {
                            TrainTogetherMarketplaceView(initialCreationMode: .physical)
                        }
                    )

                    navigationRow(
                        title: ATHLTHLocalization.choose(
                            english: "Train in the same workout",
                            norwegian: "Trene i samme økt"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Train together remotely with shared progress.",
                            norwegian: "Tren sammen på avstand med delt fremdrift."
                        ),
                        icon: "person.2.wave.2",
                        destination: {
                            TrainTogetherMarketplaceView(initialCreationMode: .remote)
                        }
                    )

                    navigationRow(
                        title: ATHLTHLocalization.choose(
                            english: "Arrange an event",
                            norwegian: "Opprett arrangement"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Invite participants to an organized activity.",
                            norwegian: "Inviter deltakere til en organisert aktivitet."
                        ),
                        icon: "calendar.badge.plus",
                        destination: {
                            CommunityEventCreateView()
                        }
                    )

                    navigationRow(
                        title: ATHLTHLocalization.choose(
                            english: "Challenge someone",
                            norwegian: "Utfordre noen"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Duels, routes and competition in Arena.",
                            norwegian: "Dueller, ruter og konkurranser i Arena."
                        ),
                        icon: "trophy",
                        destination: {
                            ATHLTHArenaHomeView()
                        }
                    )
                }
                .padding(16)
                .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Create", norwegian: "Opprett"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func navigationRow<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            ATHLTHPlanSurface {
                HStack(spacing: 13) {
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                        .frame(width: 48, height: 48)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .frame(minHeight: 52)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
