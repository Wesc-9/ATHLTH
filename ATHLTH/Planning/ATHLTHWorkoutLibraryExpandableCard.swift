import SwiftUI

/// An expandable workout-library card. Tapping the summary folds or unfolds
/// the recipe; the independent plus button opens the existing add-to-plan flow.
/// Accessory controls such as Favorites remain tappable, without nested buttons.
struct ATHLTHWorkoutLibraryExpandableCard<Accessory: View>: View {
    /// Catalog rows carry their small immutable entry until opened. They do
    /// not construct a full PlannedSession during scrolling or search.
    let workout: PlannedSession?
    let entry: WorkoutTemplateCatalogEntry?
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
        self.entry = nil
        self.subtitle = subtitle
        self.expanded = expanded
        self.onToggle = onToggle
        self.onUse = onUse
        self.accessory = accessory()
    }

    init(
        entry: WorkoutTemplateCatalogEntry,
        subtitle: String? = nil,
        expanded: Bool,
        onToggle: @escaping () -> Void,
        onUse: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.entry = entry
        self.workout = nil
        self.subtitle = subtitle
        self.expanded = expanded
        self.onToggle = onToggle
        self.onUse = onUse
        self.accessory = accessory()
    }

    private var workoutTitle: String { entry?.title ?? workout?.title ?? "" }
    private var workoutIcon: String {
        entry?.systemImage ?? workout?.kind.systemImage ?? "dumbbell"
    }
    private var stepCount: Int {
        entry?.blocks.count ?? workout?.resolvedWorkoutBlocks.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 0) {
            HStack(alignment: .top, spacing: 6) {
                Button(action: onToggle) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: workoutIcon)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 30, height: 35)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHLibraryName.workoutCard(workoutTitle, grid: false))
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
                            if !expanded {
                                if let entry {
                                    ATHLTHWorkoutGridDetails(entry: entry)
                                        .padding(.top, 3)
                                } else if let workout {
                                    ATHLTHWorkoutGridDetails(workout: workout)
                                        .padding(.top, 3)
                                }
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
                .accessibilityLabel(workoutTitle)
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
                if let entry {
                    ATHLTHWorkoutContentsPreview(
                        workout: entry.plannedSession(),
                        maximumVisibleBlocks: nil
                    )
                    .transition(.opacity)
                } else if let workout {
                    ATHLTHWorkoutContentsPreview(
                        workout: workout,
                        maximumVisibleBlocks: nil
                    )
                    .transition(.opacity)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}
