import SwiftUI

/// Share an existing personal item with one explicitly selected mutual friend.
/// Reuses the messaging library picker and its privacy-safe payload factory.
enum ATHLTHFriendQuickShareKind: String, CaseIterable, Identifiable {
    case plan, workout, route, exercise

    var id: String { rawValue }

    var allowedKinds: [MessageShareKind] {
        switch self {
        case .plan: return [.trainingPlan]
        case .workout: return [.workout, .runningWorkout]
        case .route: return [.route]
        case .exercise: return [.exercise]
        }
    }

    var title: String {
        switch self {
        case .plan:
            ATHLTHLocalization.choose(english: "Send plan", norwegian: "Send plan")
        case .workout:
            ATHLTHLocalization.choose(english: "Send workout", norwegian: "Send treningsøkt")
        case .route:
            ATHLTHLocalization.choose(english: "Send route", norwegian: "Send rute")
        case .exercise:
            ATHLTHLocalization.choose(english: "Send exercise", norwegian: "Send øvelse")
        }
    }

    var sentConfirmation: String {
        switch self {
        case .plan:
            ATHLTHLocalization.choose(english: "Plan sent", norwegian: "Planen er sendt")
        case .workout:
            ATHLTHLocalization.choose(english: "Workout sent", norwegian: "Treningsøkten er sendt")
        case .route:
            ATHLTHLocalization.choose(english: "Route sent", norwegian: "Ruten er sendt")
        case .exercise:
            ATHLTHLocalization.choose(english: "Exercise sent", norwegian: "Øvelsen er sendt")
        }
    }
}

/// Published only after the messaging backend confirms a successful send.
extension Notification.Name {
    static let athlthFriendQuickShareDidSucceed = Notification.Name(
        "athlth.friendQuickShareDidSucceed"
    )
}

struct ATHLTHFriendQuickShareRequest: Identifiable {
    let id = UUID()
    let friend: SocialProfileCard
    let kind: ATHLTHFriendQuickShareKind
}

struct ATHLTHFriendQuickShareFlow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var social: SocialStore

    let request: ATHLTHFriendQuickShareRequest

    @State private var selectedDraft: MessageShareDraft?
    @State private var note = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        Group {
            if let draft = selectedDraft {
                confirmation(for: draft)
            } else {
                MessageSharePicker(allowedKinds: request.kind.allowedKinds) { draft in
                    // Selection is not transmission. The user explicitly
                    // approves the item and named recipient on the next page.
                    errorMessage = nil
                    selectedDraft = draft
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func confirmation(for draft: MessageShareDraft) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(spacing: 12) {
                        SocialAvatar(profile: request.friend, size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Recipient", "Mottaker"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(request.friend.resolvedName)
                                .font(.headline)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            if !request.friend.usernameLabel.isEmpty {
                                Text(request.friend.usernameLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))

                    HStack(spacing: 12) {
                        Image(systemName: draft.kind.systemImage)
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            .frame(width: 46, height: 46)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(draft.subtitle ?? draft.kind.localizedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))

                    TextField(
                        tr("Personal message (optional)", "Personlig melding (valgfritt)"),
                        text: $note, axis: .vertical
                    )
                    .lineLimit(2...4)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))

                    Label(
                        tr("Only this friend will receive the selected item.",
                           "Kun denne vennen får innholdet du har valgt."),
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(request.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Back", "Tilbake")) {
                        selectedDraft = nil
                    }
                    .disabled(sending)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await send(draft) }
                } label: {
                    if sending {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        Label(
                            tr("Send to \(request.friend.resolvedName)",
                               "Send til \(request.friend.resolvedName)"),
                            systemImage: "paperplane.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.premiumGold)
                .disabled(sending || sent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
    }

    private func send(_ draft: MessageShareDraft) async {
        guard !sending, !sent,
              social.mutualFollows.contains(where: {
                  $0.userID == request.friend.userID
              })
        else {
            errorMessage = tr(
                "Sharing requires a mutual friendship.",
                "Dere må følge hverandre før du kan sende innhold."
            )
            return
        }
        sending = true
        defer { sending = false }
        errorMessage = nil
        do {
            let id = try await messaging.openConversation(with: request.friend.userID)
            let success = await messaging.send(
                to: request.friend.userID,
                conversationID: id,
                body: note.trimmingCharacters(in: .whitespacesAndNewlines),
                attachment: draft
            )
            if success {
                sent = true
                dismiss()
                NotificationCenter.default.post(
                    name: .athlthFriendQuickShareDidSucceed,
                    object: request.kind
                )
            } else {
                errorMessage = messaging.errorMessage ?? tr(
                    "Could not send the item.", "Kunne ikke sende innholdet."
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
