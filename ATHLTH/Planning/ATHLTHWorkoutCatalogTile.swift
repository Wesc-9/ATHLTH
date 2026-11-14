import SwiftUI

/// Isolated, data-only display for a catalog recipe. Parent-level filter,
/// preview and selection changes no longer compile into the tile body.
/// The source recipe remains immutable; personal workout creation happens
/// only when the user selects a workout.
struct ATHLTHWorkoutCatalogTile: View, Equatable {
    let entry: WorkoutTemplateCatalogEntry
    /// Incremented on published catalog refresh to invalidate row content.
    let catalogRevision: Int
    let compact: Bool
    let includePreview: Bool
    let history: ATHLTHLibraryWorkoutHistory.Summary?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // Avoid deep comparison of hundreds of workout blocks on every
        // unrelated state update. The catalog store owns contentRevision.
        lhs.entry.id == rhs.entry.id &&
            lhs.catalogRevision == rhs.catalogRevision &&
            lhs.compact == rhs.compact &&
            lhs.includePreview == rhs.includePreview &&
            lhs.history == rhs.history
    }

    var body: some View {
        if compact {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 44, height: 44)
                .background(ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)

            Text(ATHLTHLibraryName.workoutCard(entry.title, grid: true))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .accessibilityLabel(entry.title)

            Text(entry.categoryTitle)
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(1)

            Spacer(minLength: 0)
            HStack(spacing: 9) {
                if let minutes = entry.estimatedDurationMinutes, minutes > 0 {
                    Label("~\(minutes) min", systemImage: "clock")
                }
                if !entry.blocks.isEmpty {
                    Label(ATHLTHLocalization.choose(
                        english: "\(entry.blocks.count) parts",
                        norwegian: "\(entry.blocks.count) deler"
                    ), systemImage: "square.stack")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.96), lineWidth: 0.8)
        }
        } else {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 50, height: 50)
                .background(
                    ATHLTHPlanDesign.accentInk.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.categoryTitle.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                Text(ATHLTHLibraryName.workoutCard(entry.title, grid: false))
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .accessibilityLabel(entry.title)
                    .multilineTextAlignment(.leading)

                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 9) {
                    Label(
                        "\(entry.blocks.count) blocks",
                        systemImage:
                            "list.number"
                    )

                    if let minutes =
                        entry.estimatedDurationMinutes {
                        Label(
                            "~\(minutes) min",
                            systemImage: "clock"
                        )
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .padding(.top, 2)

                if includePreview {
                    ATHLTHWorkoutContentsPreview(blocks: entry.blocks)
                        .padding(.top, 7)
                }

                if let last = history {
                    ATHLTHLastWorkoutHistoryLabel(summary: last)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 34)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.86),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.94),
                lineWidth: 0.8
            )
        }
        }
    }
}
