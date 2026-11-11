import SwiftUI

/// Shared identity and setup card for Quick Train. Planned sessions can
/// supply their scheduled date; immediate sessions show a compact, read-only
/// start-now label instead of date/time pickers.
struct ATHLTHWorkoutDetailsCard<Details: View>: View {
    let activityTitle: String
    let symbol: String
    var name: Binding<String>? = nil
    var scheduledAt: Binding<Date>? = nil
    let details: Details

    init(
        activityTitle: String,
        symbol: String,
        name: Binding<String>? = nil,
        scheduledAt: Binding<Date>? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.activityTitle = activityTitle
        self.symbol = symbol
        self.name = name
        self.scheduledAt = scheduledAt
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTrainDesign.paleGold.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "WORKOUT DETAILS", norwegian: "ØKTDETALJER"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(activityTitle)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: scheduledAt == nil ? "NOW" : "PLANNED",
                        norwegian: scheduledAt == nil ? "NÅ" : "PLANLAGT"
                    ))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    if let scheduledAt {
                        Text(scheduledAt.wrappedValue,
                             format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption.weight(.semibold))
                    } else {
                        Text(Date.now, format: .dateTime.hour().minute())
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            if let name {
                TextField(
                    "", text: name,
                    prompt: Text(ATHLTHLocalization.choose(
                        english: "Workout name (optional)",
                        norwegian: "Øktnavn (valgfritt)"
                    ))
                    .foregroundStyle(.secondary.opacity(0.55))
                )
                .font(.subheadline.weight(.medium))
                .tint(ATHLTHTrainDesign.bronze)
                .textInputAutocapitalization(.sentences)
                .frame(minHeight: 43)
                .padding(.horizontal, 13)
                .background(ATHLTHPlanDesign.canvas,
                            in: RoundedRectangle(cornerRadius: 12))
            }

            details
        }
        .padding(15)
        .athlthTrainPaper()
        .accessibilityIdentifier("athlth-shared-workout-details")
    }
}
