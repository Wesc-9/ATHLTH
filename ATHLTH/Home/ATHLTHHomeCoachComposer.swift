import SwiftUI

/// Compact Home entry into the existing ATHLTH Coach conversation.
/// Only a user-entered message is sent; example placeholders never send.
struct ATHLTHHomeCoachComposer: View {
    @Binding var draft: String

    let hasPlannedWorkout: Bool
    let hasCoachAccess: Bool
    let onOpen: () -> Void
    let onSend: (String) -> Void

    @FocusState private var isWriting: Bool

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: String {
        ATHLTHLocalization.choose(
            english: hasPlannedWorkout
                ? "E.g. How should I approach today's workout?"
                : "E.g. Can you help me plan a workout?",
            norwegian: hasPlannedWorkout
                ? "F.eks. hvordan bør jeg trene i dag?"
                : "F.eks. kan du lage en økt til meg?"
        )
    }

    private var exampleQuestions: [String] {
        [
            ATHLTHLocalization.choose(
                english: "Help me plan a workout for today",
                norwegian: "Hjelp meg å planlegge en økt i dag"
            ),
            ATHLTHLocalization.choose(
                english: "Create a training plan with three sessions a week",
                norwegian: "Lag en treningsplan med tre økter i uken"
            ),
            ATHLTHLocalization.choose(
                english: "Can I move tomorrow's workout?",
                norwegian: "Kan vi flytte morgendagens treningsøkt?"
            ),
            ATHLTHLocalization.choose(
                english: "How is my training progressing?",
                norwegian: "Hvordan går treningsfremgangen min?"
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 28, height: 28)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .accessibilityHidden(true)

                Button(action: onOpen) {
                    HStack(spacing: 5) {
                        Text("ATHLTH Coach")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Open ATHLTH Coach conversation",
                    norwegian: "Åpne samtalen med ATHLTH Coach"
                ))

                Spacer(minLength: 4)

                if hasCoachAccess {
                    Menu {
                        ForEach(exampleQuestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                draft = suggestion
                                isWriting = true
                            }
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Ideas", norwegian: "Forslag"
                            ),
                            systemImage: "lightbulb"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(minHeight: 36)
                    }
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Choose an example to edit before sending",
                        norwegian: "Velg et eksempel du kan redigere før du sender"
                    ))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 10) {
                if hasCoachAccess {
                    TextField(
                        "",
                        text: $draft,
                        prompt: Text(placeholder)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($isWriting)
                    .onSubmit(submit)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Write to ATHLTH Coach",
                        norwegian: "Skriv til ATHLTH Coach"
                    ))

                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(
                                trimmedDraft.isEmpty
                                    ? ATHLTHPlanDesign.secondaryInk
                                    : Color.white
                            )
                            .frame(width: 38, height: 38)
                            .background(
                                trimmedDraft.isEmpty
                                    ? ATHLTHPlanDesign.selectedSurface
                                    : ATHLTHPlanDesign.accentInk,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraft.isEmpty)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Send to ATHLTH Coach",
                        norwegian: "Send til ATHLTH Coach"
                    ))
                } else {
                    Button(action: onOpen) {
                        HStack(spacing: 8) {
                            Text(ATHLTHLocalization.choose(
                                english: "Unlock personal training guidance with ATHLTH+",
                                norwegian: "Lås opp personlig treningshjelp med ATHLTH+"
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        .frame(minHeight: 38, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 7)
            .frame(minHeight: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        ATHLTHPlanDesign.accentInk.opacity(0.19),
                        lineWidth: 1
                    )
            }
        }
        .padding(13)
        .background(
            Color.white.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    ATHLTHPlanDesign.accentInk.opacity(0.12),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: ATHLTHPlanDesign.accentInk.opacity(0.035),
            radius: 10,
            y: 3
        )
    }

    private func submit() {
        let question = trimmedDraft
        guard hasCoachAccess, !question.isEmpty else { return }
        isWriting = false
        onSend(question)
    }
}
