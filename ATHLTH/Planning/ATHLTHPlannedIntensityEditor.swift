import SwiftUI

/// Clear, explicitly labelled planned targets for every non-rest step.
struct ATHLTHPlannedIntensityEditor: View {
    @Binding var block: WorkoutTemplateBlock

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var zone: Binding<Int> {
        Binding(
            get: { block.targetHeartRateZone ?? 0 },
            set: { selected in
                block.targetHeartRateZone = (1...5).contains(selected) ? selected : nil
                // A manual zone replaces conflicting imported bounds.
                block.sourceIntensityZoneLabel = nil
                block.targetHeartRatePercentMin = nil
                block.targetHeartRatePercentMax = nil
            }
        )
    }

    private var effort: Binding<Int> {
        Binding(
            get: { block.targetEffortRPE ?? 0 },
            set: { block.targetEffortRPE = (1...10).contains($0) ? $0 : nil }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("PLANNED INTENSITY", "PLANLAGT INTENSITET"))
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(ATHLTHTrainDesign.bronze)

            HStack(spacing: 10) {
                Image(systemName: "heart")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Heart rate zone", "Pulssone"))
                        .font(.subheadline.weight(.semibold))
                    Text(tr("Zone 1–5", "Sone 1–5"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(tr("Heart rate zone", "Pulssone"), selection: zone) {
                    Text(tr("None", "Ingen")).tag(0)
                    ForEach(1...5, id: \.self) { value in
                        Text((ATHLTHLocalization.isNorwegian ? "S" : "Z") + "\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(ATHLTHTrainDesign.bronze)
            }
            .frame(minHeight: 49)

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Perceived effort", "Opplevd anstrengelse"))
                        .font(.subheadline.weight(.semibold))
                    Text(tr("Scale 1–10 (RPE)", "Skala 1–10 (RPE)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(tr("Perceived effort", "Anstrengelse"), selection: effort) {
                    Text(tr("None", "Ingen")).tag(0)
                    ForEach(1...10, id: \.self) { value in
                        Text("RPE \(value)/10").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(ATHLTHTrainDesign.bronze)
            }
            .frame(minHeight: 49)

            Text(tr(
                "Planned targets only, not measured pulse or exertion.",
                "Planlagte mål, ikke målt puls eller anstrengelse."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(ATHLTHPlanDesign.selectedSurface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
