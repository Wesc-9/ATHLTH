import SwiftUI

/// The unfinished-plan context menu. Kept separate from the card so the
/// existing draft persistence, resume and delete-confirmation flows stay intact.
struct ATHLTHPlanDraftActionsPopover: View {
    let onContinue: () -> Void
    let onStartNew: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onContinue) {
                HStack(spacing: 13) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(tr("Continue planning", "Fortsett planleggingen"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 57, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                ATHLTHTrainDesign.paleGold.opacity(0.59),
                                ATHLTHTrainDesign.gold.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
            }
            .buttonStyle(.plain)

            Button(action: onStartNew) {
                HStack(spacing: 13) {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(tr("Start a new plan", "Start ny plan"))
                        .font(.body)
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 51, alignment: .leading)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(ATHLTHTrainDesign.rule.opacity(0.58))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .accessibilityHidden(true)

            Button(action: onDelete) {
                HStack(spacing: 13) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(tr("Delete draft", "Slett utkast"))
                        .font(.body)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color(red: 0.74, green: 0.23, blue: 0.21))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr(
                "Opens a confirmation before deleting this draft.",
                "Åpner en bekreftelse før utkastet slettes."
            ))
        }
        .padding(11)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 302 : 275)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                ATHLTHTrainDesign.paper.opacity(0.92),
                                ATHLTHTrainDesign.canvas.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [
                        Color.white.opacity(0.93),
                        ATHLTHTrainDesign.gold.opacity(0.62),
                        ATHLTHTrainDesign.rule.opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 0.9)
                .allowsHitTesting(false)
        }
        .shadow(color: ATHLTHTrainDesign.bronze.opacity(0.15), radius: 18, y: 8)
        .padding(4)
        .accessibilityElement(children: .contain)
    }
}
