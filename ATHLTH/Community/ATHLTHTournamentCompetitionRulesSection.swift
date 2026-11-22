import SwiftUI

/// Premium advanced rules editor shared by personal and club tournaments.
/// The published values must also be validated by the server; this view never
/// awards points or grants permission by itself.
struct ATHLTHTournamentCompetitionRulesSection: View {
    @Binding var settings: ATHLTHTournamentCompetitionSettings
    @State private var expandedAccess = false
    @State private var expandedAgreement = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Start og progresjon")
                .font(.system(size: 23, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Bestem startdato", isOn: Binding(
                    get: { settings.startsAt != nil },
                    set: { enabled in
                        settings.startsAt = enabled
                            ? Date().addingTimeInterval(86_400) : nil
                    }
                ))
                .tint(ATHLTHArenaV3Style.gold)
                if settings.startsAt != nil {
                    DatePicker(
                        "Konkurransen kan starte",
                        selection: Binding(
                            get: { settings.startsAt ?? Date() },
                            set: { settings.startsAt = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.subheadline)
                    Text("Invitasjoner og regelgodkjenning kan gjøres før start.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                Divider()
                Text("Når åpner neste øvelse?")
                    .font(.subheadline.weight(.semibold))
                Picker("Neste øvelse", selection: $settings.unlock) {
                    ForEach(ATHLTHCompetitionUnlock.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
                if settings.unlock == .interval {
                    HStack(spacing: 10) {
                        Stepper(
                            "Hver \(settings.every)",
                            value: $settings.every,
                            in: 1...settings.unit.maximumCount
                        )
                        Picker("Enhet", selection: $settings.unit) {
                            ForEach(ATHLTHCompetitionIntervalUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .font(.subheadline)
                } else {
                    Text("Neste øvelse åpnes når alle deltakere har fullført, eller den forrige fristen er utløpt. Fraværende deltakere får 0.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                Divider()
                HStack(spacing: 12) {
                    Text("Gjennomføringsfrist")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("Frist", selection: $settings.completionHours) {
                        ForEach(ATHLTHTournamentCadence.completionHours,
                                id: \.self) { hours in
                            Text(ATHLTHTournamentCadence.window(hours))
                                .tag(hours)
                        }
                    }
                    .labelsHidden()
                    .tint(ATHLTHArenaV3Style.gold)
                }
                Label(
                    "Ikke gjennomført innen fristen: 0 poeng. Uavgjort ved to uteblivelser avgjøres ikke ved loddtrekning.",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())

            DisclosureGroup(
                "Invitasjoner og godkjenning",
                isExpanded: $expandedAccess
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hvem kan invitere flere?")
                        .font(.subheadline.weight(.semibold))
                    Picker("Invitasjonsrett", selection: $settings.invitationPermission) {
                        ForEach(ATHLTHCompetitionInvitePermission.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Divider()
                    Text("Hvem godkjenner nye deltakere?")
                        .font(.subheadline.weight(.semibold))
                    Picker("Godkjenning", selection: $settings.joinApproval) {
                        ForEach(ATHLTHCompetitionJoinApproval.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Den inviterte må alltid selv godta eller avslå. Andre kan ikke samtykke på vedkommendes vegne.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .padding(.top, 10)
            }
            .font(.subheadline.weight(.semibold))
            .tint(ATHLTHArenaV3Style.gold)
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())

            DisclosureGroup(
                "Regler, premier og frivillig straff",
                isExpanded: $expandedAgreement
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    entry("Dette er lov", text: $settings.agreement.allowed,
                          hint: "F.eks. ute og tredemølle, tillatt utstyr")
                    entry("Dette er ikke lov", text: $settings.agreement.prohibited,
                          hint: "F.eks. manuell registrering eller hjelp fra andre")
                    Divider()
                    entry("Premie – 1. plass",
                          text: $settings.agreement.firstPrize,
                          hint: "Valgfritt")
                    entry("Premie – 2. plass",
                          text: $settings.agreement.secondPrize,
                          hint: "Valgfritt")
                    entry("Premie – 3. plass",
                          text: $settings.agreement.thirdPrize,
                          hint: "Valgfritt")
                    entry("Frivillig konsekvens for taper",
                          text: $settings.agreement.loserConsequence,
                          hint: "Valgfritt – må være trygt og lovlig")
                    Text("Premier og konsekvenser er kun frivillige avtaler mellom deltakerne. ATHLTH krever ikke inn penger og gjennomfører ingen straff. Alle må godkjenne vilkårene før start.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .padding(.top, 10)
            }
            .font(.subheadline.weight(.semibold))
            .tint(ATHLTHArenaV3Style.gold)
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())
        }
        .onChange(of: settings.unit) { _, unit in
            settings.every = min(settings.every, unit.maximumCount)
        }
    }

    private func entry(
        _ title: String, text: Binding<String>, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(hint, text: text, axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline.weight(.regular))
                .padding(11)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: text.wrappedValue) { _, value in
                    if value.count > 500 {
                        text.wrappedValue = String(value.prefix(500))
                    }
                }
        }
    }
}
