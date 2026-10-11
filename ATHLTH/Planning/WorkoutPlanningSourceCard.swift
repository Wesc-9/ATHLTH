import SwiftUI

/// Shared first step for personal planning, direct partner invites and
/// Train Together. Both entry points lead into SessionEditorView.
struct WorkoutPlanningSourceCard: View {
    let context: String
    let onCreateNew: () -> Void
    let onUsePlanned: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.8),
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("ATHLTH · PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "How do you want to start?",
                        norwegian: "Hvordan vil du starte?"
                    ))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                }
                Spacer()
            }
            Text(context)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            action(
                title: ATHLTHLocalization.choose(
                    english: "Start from scratch", norwegian: "Fra bunnen av"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Create an entirely new workout with all planning options.",
                    norwegian: "Bygg en ny økt med alle planleggingsvalgene."
                ),
                icon: "plus.circle.fill",
                action: onCreateNew
            )
            action(
                title: ATHLTHLocalization.choose(
                    english: "Use a planned workout", norwegian: "Bruk planlagt økt"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Reuse and edit a workout you already planned.",
                    norwegian: "Hent og tilpass en økt du allerede har planlagt."
                ),
                icon: "calendar.badge.clock",
                action: onUsePlanned
            )
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.98),
                             ATHLTHTheme.surfaceStone.opacity(0.87),
                             ATHLTHTheme.cardWarm.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(LinearGradient(
                    colors: [Color.white,
                             ATHLTHTheme.accentDeep.opacity(0.17),
                             Color.white.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.07),
                radius: 16, x: 0, y: 7)
    }

    private func action(
        title: String, subtitle: String, icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 43, height: 43)
                    .background(ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 3)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(ATHLTHTheme.border.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
