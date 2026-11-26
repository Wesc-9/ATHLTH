import SwiftUI

/// Reusable, deliberately unanchored decision sheet for unfinished workout
/// and training-plan drafts. Never calls a destructive action when dismissed
/// interactively: swipe-down means "keep editing" on the underlying screen.
struct ATHLTHDiscardDraftSheet: View {
    enum Kind: Equatable {
        case workout
        case standaloneWorkoutDraft
        case trainingPlan
        case savedTrainingPlanDraft
        case competition

        var title: String {
            switch self {
            case .competition:
                return ATHLTHLocalization.choose(
                    english: "Leave setup?",
                    norwegian: "Avslutte oppsett?"
                )
            case .workout:
                return ATHLTHLocalization.choose(
                    english: "Leave workout planning?",
                    norwegian: "Avslutte øktplanleggingen?"
                )
            case .standaloneWorkoutDraft:
                return ATHLTHLocalization.choose(
                    english: "What do you want to do with this draft?",
                    norwegian: "Hva vil du gjøre med utkastet?"
                )
            case .trainingPlan:
                return ATHLTHLocalization.choose(
                    english: "Keep your plan for later?",
                    norwegian: "Ta vare på planen din?"
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
            case .competition:
                return ATHLTHLocalization.choose(
                    english: "Your competition is not published yet. Keep your draft to continue later, or discard only this unfinished setup.",
                    norwegian: "Konkurransen er ikke publisert ennå. Behold utkastet for å fortsette senere, eller forkast dette oppsettet."
                )
            case .workout:
                return ATHLTHLocalization.choose(
                    english: "Your changes are not yet saved as a workout. Keep editing or save the draft for later.",
                    norwegian: "Endringene er ikke lagret som treningsøkt. Du kan fortsette eller beholde utkastet til senere."
                )
            case .standaloneWorkoutDraft:
                return ATHLTHLocalization.choose(
                    english: "Keep editing, save the draft for later or permanently delete it. Your planned workouts are unaffected.",
                    norwegian: "Fortsett å redigere, behold utkastet til senere eller slett det. Planlagte økter blir ikke berørt."
                )
            case .trainingPlan:
                return ATHLTHLocalization.choose(
                    english: "Save your progress and return to the same day and workout whenever you like.",
                    norwegian: "Lagre fremdriften og fortsett på samme dag og treningsøkt når du ønsker."
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
            case .workout, .trainingPlan, .competition:
                return ATHLTHLocalization.choose(
                    english: "Discard draft", norwegian: "Forkast utkast"
                )
            case .savedTrainingPlanDraft, .standaloneWorkoutDraft:
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
    // Embedded callers own dismissal; do not dismiss their navigation host.
    var embedded = false

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private var prioritizesSaving: Bool { kind == .trainingPlan || kind == .competition }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if kind == .trainingPlan {
                    Text("A T H L T H   /   P L A N")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(.bottom, 17)
                }

                Image(systemName: kind == .competition ? "doc.text" : kind == .trainingPlan
                    ? "square.and.arrow.down" : "square.and.pencil")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 50, height: 50)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 17))
                    .accessibilityHidden(true)
                    .padding(.bottom, 14)

                Text(kind.title)
                    .font(.system(size: prioritizesSaving ? 27 : 23,
                                  weight: prioritizesSaving ? .medium : .semibold,
                                  design: prioritizesSaving ? .serif : .rounded))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)

                Text(kind.description)
                    .font(.system(size: 14))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                VStack(spacing: 10) {
                    if prioritizesSaving {
                        if let onSaveDraftAndClose {
                            Button(action: onSaveDraftAndClose) {
                                Label(
                                    kind == .competition
                                        ? tr("Keep draft", "Behold utkast")
                                        : tr("Save draft and close", "Lagre utkast og lukk"),
                                    systemImage: "square.and.arrow.down"
                                )
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(bronze.gradient,
                                            in: RoundedRectangle(cornerRadius: 16))
                            }
                            .accessibilityIdentifier(kind == .competition
                                ? "athlth-competition-keep-draft" : "athlth-plan-save-draft-and-close")
                        }

                        Button {
                            onKeepEditing()
                            if !embedded { dismiss() }
                        } label: {
                            Text(tr("Continue editing", "Fortsett redigering"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity, minHeight: 49)
                                .background(.white,
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 1)
                                }
                        }
                        .accessibilityIdentifier(kind == .competition
                            ? "athlth-competition-keep-editing" : "athlth-plan-keep-editing")
                    } else {
                        Button {
                            onKeepEditing()
                            if !embedded { dismiss() }
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
                            Button(action: onSaveDraftAndClose) {
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
                    }

                    Divider()
                        .overlay(ATHLTHPlanDesign.warmDivider.opacity(0.55))
                        .padding(.vertical, 5)

                    Button(role: .destructive) {
                        onDiscard()
                    } label: {
                        Label(kind.destructiveTitle, systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.66, green: 0.25, blue: 0.24))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(kind == .competition
                        ? "athlth-competition-discard-draft" : "athlth-plan-discard-draft")
                    .accessibilityHint(tr(
                        "Permanently delete only this unfinished draft",
                        "Sletter kun dette uferdige utkastet permanent"
                    ))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, kind == .trainingPlan ? 29 : 23)
            .padding(.bottom, 22)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .presentationDetents(kind == .competition
            ? [.height(410), .large]
            : kind == .trainingPlan
                ? [.height(435), .large]
            : onSaveDraftAndClose == nil
                ? [.height(310), .medium, .large]
                : [.height(383), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .accessibilityElement(children: .contain)
    }

}

 
/// Compact day-switch decision, shared by the weekday rail and the back
/// action. The parent only navigates after the builder has saved or deleted
/// its checkpoint. Interactive dismissal never discards a workout.
struct ATHLTHFocusedWorkoutDraftDecisionSheet: View {
    let destination: Date?
    let onKeepEditing: () -> Void
    let onSaveDraftAndClose: () -> Void
    let onDiscard: () -> Void

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var heading: String {
        destination == nil
            ? tr("Keep your workout?", "Beholde øktutkastet?")
            : tr("Change training day?", "Bytte treningsdag?")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 13) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(bronze)
                        .frame(width: 52, height: 52)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATHLTH · " + tr("DRAFT", "UTKAST"))
                            .font(.caption2.weight(.bold))
                            .tracking(1.8)
                            .foregroundStyle(bronze)
                        Text(heading)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(action: onKeepEditing) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .frame(width: 44, height: 44)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Cancel", "Avbryt"))
                }

                if let destination {
                    Label(destination.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                          systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(bronze)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                }

                Text(tr("Your workout is not scheduled yet. Save it as a draft to continue later, or delete only this unfinished workout.",
                        "Økten er ikke planlagt ennå. Behold den som utkast for å fortsette senere, eller slett kun denne uferdige økten."))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button(action: onSaveDraftAndClose) {
                        Label(destination == nil
                              ? tr("Keep draft and close", "Behold utkast og lukk")
                              : tr("Keep draft and change day", "Behold utkast og bytt dag"),
                              systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(bronze.gradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("athlth-focused-keep-draft")

                    Button(action: onKeepEditing) {
                        Label(tr("Continue editing", "Fortsett å redigere"),
                              systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
                            }
                    }
                    .accessibilityIdentifier("athlth-focused-continue-editing")

                    Divider().padding(.vertical, 2)
                    Button(role: .destructive, action: onDiscard) {
                        Label(destination == nil
                              ? tr("Delete draft and close", "Slett utkast og lukk")
                              : tr("Delete draft and change day", "Slett utkast og bytt dag"),
                              systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.66, green: 0.25, blue: 0.24))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("athlth-focused-delete-draft")
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .presentationDetents([.height(destination == nil ? 390 : 450), .large])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("athlth-focused-draft-decision")
    }
}
