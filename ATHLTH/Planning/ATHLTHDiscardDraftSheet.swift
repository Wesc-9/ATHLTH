import SwiftUI

/// Reusable, deliberately unanchored decision sheet for unfinished workout
/// and training-plan drafts. Never calls a destructive action when dismissed
/// interactively: swipe-down means "keep editing" on the underlying screen.
struct ATHLTHDiscardDraftSheet: View {
    enum Kind: Equatable {
        case workout
        case trainingPlan
        case savedTrainingPlanDraft

        var title: String {
            switch self {
            case .workout:
                return ATHLTHLocalization.choose(
                    english: "Leave this workout?",
                    norwegian: "Avslutte treningsøkten?"
                )
            case .trainingPlan:
                return ATHLTHLocalization.choose(
                    english: "Leave this training plan?",
                    norwegian: "Avslutte treningsplanen?"
                )
            case .savedTrainingPlanDraft:
                return ATHLTHLocalization.choose(
                    english: "Delete this plan draft?",
                    norwegian: "Slette dette planutkastet?"
                )
            }
        }

        var description: String {
            switch self {
            case .workout:
                return ATHLTHLocalization.choose(
                    english: "Your changes are not yet saved as a workout. Keep editing or save the draft for later.",
                    norwegian: "Endringene er ikke lagret som treningsøkt. Du kan fortsette eller beholde utkastet til senere."
                )
            case .trainingPlan:
                return ATHLTHLocalization.choose(
                    english: "Your plan is not finished. Save the draft to continue building it later.",
                    norwegian: "Treningsplanen er ikke ferdig. Behold utkastet for å fortsette senere."
                )
            case .savedTrainingPlanDraft:
                return ATHLTHLocalization.choose(
                    english: "Only this unfinished draft will be removed. Your saved plans and workout history stay untouched.",
                    norwegian: "Kun dette uferdige utkastet slettes. Lagrede planer og treningshistorikk beholdes."
                )
            }
        }

        var destructiveTitle: String {
            switch self {
            case .workout, .trainingPlan:
                return ATHLTHLocalization.choose(
                    english: "Discard draft", norwegian: "Forkast utkast"
                )
            case .savedTrainingPlanDraft:
                return ATHLTHLocalization.choose(
                    english: "Delete draft", norwegian: "Slett utkast"
                )
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let kind: Kind
    let onKeepEditing: () -> Void
    let onSaveDraftAndClose: (() -> Void)?
    let onDiscard: () -> Void
    var errorMessage: String? = nil

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 48, height: 48)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text(kind.title)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(kind.description)
                        .font(.system(size: 14))
                        .foregroundStyle(ink.opacity(0.64))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 9) {
                    Button {
                        onKeepEditing()
                        dismiss()
                    } label: {
                        Label(
                            kind == .savedTrainingPlanDraft
                                ? tr("Keep draft", "Behold utkast")
                                : tr("Keep editing", "Fortsett å redigere"),
                            systemImage: kind == .savedTrainingPlanDraft
                                ? "checkmark" : "arrow.uturn.backward"
                        )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(bronze.gradient,
                                        in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let onSaveDraftAndClose {
                        Button {
                            onSaveDraftAndClose()
                        } label: {
                            Label(tr("Save draft and close", "Lagre utkast og lukk"),
                                  systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity, minHeight: 49)
                                .background(ATHLTHPlanDesign.selectedSurface,
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(bronze.opacity(0.13), lineWidth: 0.7)
                                }
                        }
                    }

                    Button(role: .destructive) {
                        onDiscard()
                    } label: {
                        Label(kind.destructiveTitle, systemImage: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.74, green: 0.19, blue: 0.20))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint(tr(
                        "Permanently delete only this unfinished draft",
                        "Sletter kun dette uferdige utkastet permanent"
                    ))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 23)
            .padding(.bottom, 22)
            .frame(maxWidth: 470)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .presentationDetents(onSaveDraftAndClose == nil
            ? [.height(310), .medium, .large]
            : [.height(383), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .accessibilityElement(children: .contain)
    }
}
