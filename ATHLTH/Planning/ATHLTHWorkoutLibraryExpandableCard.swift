import SwiftUI

/// An expandable workout-library card. Tapping the summary folds or unfolds
/// the recipe; the independent plus button opens the existing add-to-plan flow.
/// Accessory controls such as Favorites remain tappable, without nested buttons.
struct ATHLTHWorkoutLibraryExpandableCard<Accessory: View>: View {
    let workout: PlannedSession
    var subtitle: String? = nil
    let expanded: Bool
    let onToggle: () -> Void
    let onUse: () -> Void
    let accessory: Accessory

    init(
        workout: PlannedSession,
        subtitle: String? = nil,
        expanded: Bool,
        onToggle: @escaping () -> Void,
        onUse: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.workout = workout
        self.subtitle = subtitle
        self.expanded = expanded
        self.onToggle = onToggle
        self.onUse = onUse
        self.accessory = accessory()
    }

    private var stepCount: Int { workout.resolvedWorkoutBlocks.count }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 0) {
            HStack(alignment: .top, spacing: 6) {
                Button(action: onToggle) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: workout.kind.systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 30, height: 35)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.title)
                                .font(.headline)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            HStack(spacing: 6) {
                                Text(ATHLTHLocalization.choose(
                                    english: "\(stepCount) steps",
                                    norwegian: "\(stepCount) øktdeler"
                                ))
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workout.title)
                .accessibilityValue(ATHLTHLocalization.choose(
                    english: expanded ? "Expanded" : "Collapsed",
                    norwegian: expanded ? "Utvidet" : "Lukket"
                ))
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Double tap to show or hide workout steps",
                    norwegian: "Dobbelttrykk for å vise eller skjule øktdelene"
                ))

                accessory

                Button(action: onUse) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Add workout", norwegian: "Legg til økt"
                ))
            }

            if expanded {
                Divider()
                ATHLTHWorkoutContentsPreview(
                    workout: workout,
                    maximumVisibleBlocks: nil
                )
                .transition(.opacity)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}
