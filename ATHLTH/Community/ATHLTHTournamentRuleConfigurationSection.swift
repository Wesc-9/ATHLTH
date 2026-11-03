import SwiftUI

/// Rules are chosen before invitations become ready. The compact controls
/// intentionally avoid large cards and keep every choice readable on iPhone.
struct ATHLTHTournamentRuleConfigurationSection: View {
    @Binding var activities: Set<ATHLTHTournamentActivity>
    @Binding var authority: ATHLTHTournamentRulesAuthority
    @Binding var cadenceDays: Int
    @Binding var completionHours: Int

    private let columns = [GridItem(.flexible(), spacing: 9),
                           GridItem(.flexible(), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aktiviteter og regler")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)

            Text("Velg alt som er tillatt. Deltakerne kan bare foreslå øvelser fra disse aktivitetene.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(ATHLTHTournamentActivity.allCases) { activity in
                    Button {
                        if activities.contains(activity) {
                            activities.remove(activity)
                        } else {
                            activities.insert(activity)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: activity.symbol)
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(ATHLTHArenaV3Style.gold)
                                .frame(width: 24)
                            Text(activity.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                            Spacer(minLength: 1)
                            Image(systemName: activities.contains(activity)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(activities.contains(activity)
                                                 ? ATHLTHArenaV3Style.gold
                                                 : ATHLTHArenaV3Style.secondary)
                        }
                        .padding(.horizontal, 11)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(ATHLTHArenaV3Style.panel())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        activities.contains(activity) ? "Valgt" : "Ikke valgt"
                    )
                }
            }

            if activities.isEmpty {
                Label("Velg minst én tillatt aktivitet.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Hvem bestemmer reglene?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
                .padding(.top, 4)

            ForEach(ATHLTHTournamentRulesAuthority.allCases) { option in
                Button {
                    authority = option
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: option == .owner
                              ? "person.crop.circle" : "person.3")
                            .font(.title3.weight(.ultraLight))
                            .frame(width: 30)
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHArenaV3Style.ink)
                            Text(option.subtitle)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        }
                        Spacer(minLength: 1)
                        Image(systemName: authority == option
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 13) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ny øvelse")
                            .font(.subheadline.weight(.semibold))
                        Text("Hvor ofte en ny øvelse åpner")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    Spacer(minLength: 1)
                    Picker("Intervall", selection: $cadenceDays) {
                        ForEach(ATHLTHTournamentCadence.options, id: \.self) { days in
                            Text(ATHLTHTournamentCadence.title(for: days))
                                .tag(days)
                        }
                    }
                    .labelsHidden()
                    .tint(ATHLTHArenaV3Style.gold)
                }

                Divider().opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gjennomføringsfrist")
                            .font(.subheadline.weight(.semibold))
                        Text("Tid fra øvelsen blir tilgjengelig")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }
                    Spacer(minLength: 1)
                    Picker("Frist", selection: $completionHours) {
                        ForEach(ATHLTHTournamentCadence.completionHours,
                                id: \.self) { hours in
                            Text(ATHLTHTournamentCadence.window(hours))
                                .tag(hours)
                        }
                    }
                    .labelsHidden()
                    .tint(ATHLTHArenaV3Style.gold)
                }
            }
            .font(.subheadline)
            .foregroundStyle(ATHLTHArenaV3Style.ink)
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())

            if completionHours > cadenceDays * 24 {
                Label("Øvelser kan overlappe. Flere frister kan derfor være aktive samtidig.",
                      systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            if authority == .group {
                Text("Arrangørens valg er et første forslag. Deltakerne kan sende alternativer, og et flertall må godkjenne reglene før øvelsene velges og lobbyen kan bli klar.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
