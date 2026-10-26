import SwiftUI

/// The fourth visible step for advanced planning. Both paths ultimately
/// produce the same TrainingPlan; switching paths never discards setup data.
struct ATHLTHPlanBuildMethodEntryView: View {
    let prefersAI: Bool
    let planWeeks: Int
    let trainingDays: Int
    let focusTitle: String
    let onSelectManual: () -> Void
    let onSelectAI: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze
    private let secondary = ATHLTHTrainDesign.secondary
    private let gold = ATHLTHTrainDesign.gold
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private func localized(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            introduction

            VStack(spacing: 13) {
                buildCard(
                    title: localized("Build it yourself", "Bygg selv"),
                    subtitle: localized(
                        "Choose each workout, exercise and interval. All details stay in your hands.",
                        "Velg økter, øvelser og intervaller selv. Du bestemmer alle detaljene."
                    ),
                    image: "PlanEntryAdvanced",
                    icon: "calendar.badge.plus",
                    features: [
                        localized("Week overview", "Ukeoversikt"),
                        localized("Edit every workout", "Rediger alle økter")
                    ],
                    selected: !prefersAI,
                    action: onSelectManual
                )
                buildCard(
                    title: "ATHLTH AI",
                    subtitle: localized(
                        "Get a tailored proposal based on your goal and availability. Review it before saving.",
                        "Få et personlig forslag ut fra målet ditt og når du kan trene. Du godkjenner før lagring."
                    ),
                    image: "GoalRunning",
                    icon: "sparkles",
                    features: [
                        localized("Suggested workouts", "Foreslåtte økter"),
                        localized("Fully editable", "Kan redigeres")
                    ],
                    selected: prefersAI,
                    action: onSelectAI
                )
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(bronze)
                    Text(localized("Your setup is saved", "Vi tar med valgene dine"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                }
                Text(
                    "\(focusTitle) · \(planWeeks) " +
                    localized("weeks", "uker") +
                    " · \(trainingDays) " +
                    localized("sessions a week", "økter per uke")
                )
                .font(.system(size: 11))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(localized(
                    "You can switch to AI later without losing your manually planned sessions.",
                    "Du kan be AI om forslag senere uten å miste øktene du allerede har planlagt."
                ))
                .font(.system(size: 11))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(rule.opacity(0.45), lineWidth: 0.7)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(bronze)
            Text(localized("How would you like\nto build your plan?",
                           "Hvordan vil du\nbygge planen?"))
                .font(.system(size: typeSize.isAccessibilitySize ? 29 : 35,
                              weight: .regular, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(localized(
                "Choose the approach that suits you. The result is always your own editable training plan.",
                "Velg det som passer deg. Uansett får du en treningsplan du kan endre fritt."
            ))
            .font(.system(size: 12.5))
            .foregroundStyle(secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
    }

    private func buildCard(
        title: String,
        subtitle: String,
        image: String,
        icon: String,
        features: [String],
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .leading) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Image(image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width * 0.64,
                                       height: geometry.size.height)
                                .clipped()
                                .accessibilityHidden(true)
                        }
                    }
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white.opacity(0.98), location: 0.32),
                            .init(color: .white.opacity(0.79), location: 0.59),
                            .init(color: .white.opacity(0.05), location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    HStack(alignment: .top, spacing: 9) {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(bronze)
                                .frame(width: 37, height: 37)
                                .background(ATHLTHTrainDesign.paleGold.opacity(0.6),
                                            in: Circle())
                            Text(title)
                                .font(.system(size: 25, weight: .medium, design: .serif))
                                .foregroundStyle(ink)
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 90)
                        Spacer(minLength: 0)
                    }
                    .padding(15)
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: selected ? "checkmark" : "circle")
                                .font(.system(size: selected ? 13 : 27,
                                              weight: .semibold))
                                .foregroundStyle(selected ? Color.white : ink.opacity(0.37))
                                .frame(width: 32, height: 32)
                                .background {
                                    if selected { Circle().fill(gold) }
                                }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(13)
                    .accessibilityHidden(true)
                }
                .frame(height: typeSize.isAccessibilitySize ? 199 : 155)
                .clipped()
                Rectangle().fill(rule.opacity(0.45)).frame(height: 0.7)
                HStack(spacing: 12) {
                    ForEach(features, id: \.self) { feature in
                        Label(feature, systemImage: "checkmark")
                            .font(.system(size: 10))
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(selected ? gold : rule.opacity(0.5),
                                  lineWidth: selected ? 1.5 : 0.7)
            }
            .shadow(color: ink.opacity(selected ? 0.09 : 0.04),
                    radius: selected ? 13 : 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
