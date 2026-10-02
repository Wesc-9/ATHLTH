import SwiftUI

struct CommunityGroupManualStrengthResultView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store:
        CommunityGroupAdvancedStore

    let group: CommunityGroupRecord
    let challenge:
        CommunityGroupChallengeRecord
    let onSaved: () -> Void

    @State private var valueText = ""
    @State private var note = ""
    @State private var saving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Manual Result") {
                    HStack {
                        TextField(
                            valuePlaceholder,
                            text: $valueText
                        )
                        .keyboardType(.decimalPad)

                        Text(challenge.metric.unit)
                            .foregroundStyle(.secondary)
                    }

                    TextField(
                        "Note (optional)",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    Label(
                        "This result will be clearly marked Manual in the challenge.",
                        systemImage: "hand.tap.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Text(
                        "Use this only when the strength result was not captured automatically by ATHLTH."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? "Saving…"
                            : "Save"
                    ) {
                        save()
                    }
                    .disabled(
                        saving ||
                        (resolvedValue ?? 0) <= 0
                    )
                }
            }
            .alert(
                "Could Not Save Result",
                isPresented: Binding(
                    get: {
                        localError != nil ||
                        store.errorMessage != nil
                    },
                    set: {
                        if !$0 {
                            localError = nil
                            store.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    localError ??
                    store.errorMessage ??
                    ""
                )
            }
        }
    }

    private var resolvedValue: Double? {
        Double(
            valueText
                .replacingOccurrences(
                    of: ",",
                    with: "."
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }

    private var valuePlaceholder: String {
        switch challenge.metric {
        case .strengthVolume:
            return "Total volume"
        case .heaviestWeight:
            return "Weight"
        case .strengthReps:
            return "Reps"
        default:
            return "Result"
        }
    }

    private func save() {
        guard let value = resolvedValue,
              value > 0
        else {
            localError =
                "Enter a result greater than zero."
            return
        }

        Task {
            saving = true

            let ok =
                await store
                    .submitManualStrengthResult(
                        challengeID:
                            challenge.id,
                        contribution: value,
                        note: note
                    )

            saving = false

            if ok {
                await store.loadChallenge(
                    groupID: group.id,
                    challengeID:
                        challenge.id
                )
                onSaved()
                dismiss()
            }
        }
    }
}
