import SwiftUI

/// Each injury has its own affected area and training limitation. Adding or
/// deleting a row never changes another row's limitation or grants AI consent.
struct ATHLTHCoachInjuryEntriesView: View {
    @Binding var intake: ATHLTHAIProgramIntake
    let areas: [String]
    let areaTitle: (String) -> String

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                intake.injuryStatus = .none
                intake.injuries = []
                intake.injuryAreas = []
                intake.injurySeverity = nil
                intake.injuryRestriction = nil
                intake.injuryNotes = ""
                intake.excludedMovements = ""
                intake.healthSharingAuthorized = false
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: intake.injuryStatus == .none
                        ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(tr("No injuries or limitations",
                            "Ingen skader eller begrensninger"))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(
                    ATHLTHTrainDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(intake.injuryStatus == .none ? .isSelected : [])

            if intake.injuryStatus == .considerations {
                ForEach($intake.injuries) { $injury in
                    HStack(spacing: 7) {
                        Menu {
                            ForEach(areas, id: \.self) { area in
                                Button(areaTitle(area)) {
                                    injury.area = area
                                    intake.healthSharingAuthorized = false
                                }
                            }
                        } label: {
                            selectorLabel(
                                injury.area.map(areaTitle) ??
                                tr("Select area", "Velg område")
                            )
                        }

                        Menu {
                            ForEach(ATHLTHAIProgramIntake.InjuryCondition.allCases) { condition in
                                Button(condition.title) {
                                    injury.condition = condition
                                    intake.healthSharingAuthorized = false
                                }
                            }
                        } label: {
                            selectorLabel(
                                injury.condition?.title ??
                                tr("Select limitation", "Velg tilstand")
                            )
                        }

                        Button {
                            intake.injuries.removeAll { $0.id == injury.id }
                            intake.healthSharingAuthorized = false
                            if intake.injuries.isEmpty {
                                intake.injuryStatus = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                                .frame(width: 36, height: 44)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("Remove injury", "Fjern skade"))
                    }
                }
            }

            Button {
                if intake.injuryStatus != .considerations {
                    intake.injuryStatus = .considerations
                    intake.injuries = []
                    intake.injuryAreas = []
                    intake.injurySeverity = nil
                    intake.injuryRestriction = nil
                }
                intake.injuries.append(.init())
                intake.healthSharingAuthorized = false
            } label: {
                Label(
                    tr("Add injury or limitation", "Legg til skade eller begrensning"),
                    systemImage: "plus"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 49)
                .background(
                    ATHLTHTrainDesign.bronze,
                    in: RoundedRectangle(cornerRadius: 15)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func selectorLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            ATHLTHTrainDesign.paper,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }
}
