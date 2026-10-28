import SwiftUI

/// Inline editor in the one private Health Profile. These selections never
/// change Apple Health values, a training plan, or an AI consent preference.
struct ATHLTHInjuryRestrictionsEditor: View {
    @Binding var restrictions: [ATHLTHInjuryRestriction]
    @State private var editing: ATHLTHInjuryRestriction?
    @State private var deleting: ATHLTHInjuryRestriction?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(tr("Injuries and limitations", "Skader og begrensninger"),
                      systemImage: "figure.stand")
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Button {
                    editing = ATHLTHInjuryRestriction()
                } label: {
                    Label(tr("Add", "Legg til"), systemImage: "plus")
                }
                .font(.subheadline.weight(.semibold))
                .tint(ATHLTHPlanDesign.accentInk)
            }

            Text(tr(
                "Choose a body area and how much you can train it. You can add several separate restrictions, one for each area.",
                "Velg kroppsområde og hvor mye du kan belaste det. Du kan legge inn flere hensyn for forskjellige områder."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            if restrictions.isEmpty {
                Label(tr("No restrictions registered", "Ingen begrensninger registrert"),
                      systemImage: "checkmark.shield")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 13))
            } else {
                ForEach(restrictions) { restriction in
                    HStack(spacing: 10) {
                        Button {
                            editing = restriction
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(restriction.area.title +
                                    (restriction.side == .unspecified ? "" :
                                     " · " + restriction.side.title))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(restriction.level.title)
                                    .font(.caption)
                                    .foregroundStyle(restriction.level == .avoid
                                        ? Color.red : ATHLTHPlanDesign.accentInk)
                                if !restriction.notes.isEmpty {
                                    Text(restriction.notes)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(tr("Edit this restriction", "Rediger begrensningen"))
                        Button {
                            deleting = restriction
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(tr("Delete restriction", "Slett begrensning"))
                        .buttonStyle(.plain)
                        .tint(.secondary)
                    }
                    .padding(11)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                }
            }

            Label(tr(
                "Private by default. Coach sees these details only if you explicitly choose to include them in an AI request.",
                "Privat som standard. Coach får bare se disse opplysningene dersom du aktivt velger å dele dem for en AI-forespørsel."
            ), systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
        .sheet(item: $editing) { entry in
            ATHLTHInjuryRestrictionEntryView(initial: entry) { saved in
                if let index = restrictions.firstIndex(where: { $0.id == saved.id }) {
                    restrictions[index] = saved
                } else {
                    restrictions.append(saved)
                }
                editing = nil
            }
        }
        .confirmationDialog(
            tr("Remove this restriction?", "Fjerne denne begrensningen?"),
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Remove", "Fjern"), role: .destructive) {
                guard let deleting else { return }
                restrictions.removeAll { $0.id == deleting.id }
                self.deleting = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) { deleting = nil }
        }
    }
}

struct ATHLTHInjuryRestrictionEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ATHLTHInjuryRestriction) -> Void
    @State private var draft: ATHLTHInjuryRestriction

    init(
        initial: ATHLTHInjuryRestriction,
        onSave: @escaping (ATHLTHInjuryRestriction) -> Void
    ) {
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Where is the limitation?", "Hvor er begrensningen?")) {
                    Picker(tr("Body area", "Kroppsområde"), selection: $draft.area) {
                        ForEach(ATHLTHInjuryArea.allCases) { area in
                            Text(area.title).tag(area)
                        }
                    }
                    Picker(tr("Side", "Side"), selection: $draft.side) {
                        ForEach(ATHLTHInjurySide.allCases) { side in
                            Text(side.title).tag(side)
                        }
                    }
                }
                Section {
                    Picker(tr("How limited?", "Hvor stor begrensning?"),
                           selection: $draft.level) {
                        ForEach(ATHLTHInjuryRestrictionLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } footer: {
                    Text(tr(
                        "Cannot train/load means Coach must not suggest exercises that stress this area. For other levels, Coach should ask for safe movements and adjust the load.",
                        "Kan ikke trene/belaste betyr at Coach ikke skal foreslå øvelser som belaster området. Ved andre nivåer skal Coach ta hensyn og avklare trygge bevegelser."
                    ))
                }
                Section {
                    TextField(
                        tr("Optional details, such as movements to avoid",
                           "Valgfritt: f.eks. bevegelser som må unngås"),
                        text: $draft.notes, axis: .vertical
                    )
                    .lineLimit(2...4)
                } header: {
                    Text(tr("Additional details", "Tilleggsopplysninger"))
                }
            }
            .navigationTitle(tr("Training limitation", "Treningshensyn"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Lagre")) {
                        draft.notes = String(draft.notes.prefix(500))
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}
