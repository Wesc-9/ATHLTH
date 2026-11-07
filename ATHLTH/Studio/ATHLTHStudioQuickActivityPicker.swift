import SwiftUI

/// Reuses every Quick Start supported by the iPhone training engine.
/// Studio never creates a separate exercise or workout implementation.
enum ATHLTHStudioQuickActivityCatalog {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let request: ATHLTHTrainNavigationRequest
    }

    static var entries: [Entry] {
        [
            Entry(
                id: "running",
                title: ATHLTHLocalization.choose(english: "Run", norwegian: "Løping"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Free, route or structured run",
                    norwegian: "Fri løping, rute eller treningsøkt"
                ),
                symbol: "figure.run",
                request: .quick(.running)
            ),
            Entry(
                id: "walking",
                title: ATHLTHLocalization.choose(english: "Walk", norwegian: "Gåtur"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Indoor or outdoor walk",
                    norwegian: "Gåtur inne eller ute"
                ),
                symbol: "figure.walk",
                request: .quick(.walking)
            ),
            Entry(
                id: "strength",
                title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Gym or at home",
                    norwegian: "På treningssenter eller hjemme"
                ),
                symbol: "dumbbell.fill",
                request: .quick(.strength)
            )
        ] + CustomQuickWorkoutActivity.allCases.map { activity in
            Entry(
                id: activity.rawValue,
                title: activity.localizedTitle,
                subtitle: activity.localizedSubtitle,
                symbol: activity.systemImage,
                request: .customQuickActivity(activity)
            )
        }
    }
}

/// iPad-only activity selector, presented before the existing Quick Start.
/// Choosing an activity dismisses this sheet; the parent opens the training
/// workspace after dismissal so two modal presentations never overlap.
struct ATHLTHStudioQuickActivityPicker: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (ATHLTHTrainNavigationRequest) -> Void

    private let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
    private let gold = Color(red: 0.68, green: 0.53, blue: 0.32)
    private let outline = Color(red: 0.88, green: 0.85, blue: 0.80)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "What would you like to train?",
                            norwegian: "Hva vil du trene?"
                        ))
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(ink)

                        Text(ATHLTHLocalization.choose(
                            english: "Choose an activity to open its Quick Start. No workout is added to your calendar.",
                            norwegian: "Velg aktivitet for å åpne hurtigstart. Økten legges ikke til i kalenderen."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 174), spacing: 11)],
                        spacing: 11
                    ) {
                        ForEach(ATHLTHStudioQuickActivityCatalog.entries) { choice in
                            Button {
                                onSelect(choice.request)
                            } label: {
                                HStack(alignment: .top, spacing: 11) {
                                    Image(systemName: choice.symbol)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(gold)
                                        .frame(width: 35, height: 35)
                                        .background(gold.opacity(0.11),
                                                    in: RoundedRectangle(cornerRadius: 12))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(choice.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ink)
                                        Text(choice.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 79,
                                       alignment: .topLeading)
                                .padding(12)
                                .background(.white,
                                            in: RoundedRectangle(cornerRadius: 17))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 17)
                                        .strokeBorder(outline.opacity(0.75), lineWidth: 0.8)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 17))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Open Quick Start setup",
                                norwegian: "Åpne oppsett for hurtigstart"
                            ))
                            .accessibilityIdentifier(
                                "athlth-ipad-quick-activity-" + choice.id
                            )
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.986, green: 0.980, blue: 0.970))
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Train now", norwegian: "Tren nå"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("athlth-ipad-quick-activity-picker")
    }
}
