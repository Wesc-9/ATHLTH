import SwiftUI

/// A compact, premium identity card that uses the actual workout title,
/// duration and notes rather than synthesizing a second recommendation.
struct HomeDailyRecommendedWorkoutHero: View {
    let workout: PlannedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ATHLTHLocalization.choose(
                english: "TODAY'S RECOMMENDATION",
                norwegian: "DAGENS ANBEFALING"
            ))
            .font(.caption2.weight(.bold))
            .tracking(1.6)
            .foregroundStyle(ATHLTHTrainDesign.bronze)

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: workout.kind.systemImage)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 56, height: 56)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(workout.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let minutes = workout.durationMinutes {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let notes = workout.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Rectangle()
                    .fill(ATHLTHPlanDesign.outline.opacity(0.7))
                    .frame(height: 0.7)

                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ATHLTHPlanDesign.surface,
            in: RoundedRectangle(cornerRadius: 21)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }
}
