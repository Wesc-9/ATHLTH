import SwiftUI

/// Explicit opt-in control for training-plan synchronization on iPad.
/// Plans may contain personal notes; Apple Health samples, routes and
/// completed workout data are not uploaded by this plan-only service.
struct ATHLTHStudioPlanSyncPanel: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync: ATHLTHStudioPlanSyncStore

    @State private var showingDisableConfirmation = false
    @State private var pendingResolution: ATHLTHStudioPlanSyncStore.Conflict?
    @State private var preferCloud = false

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: sync.enabled ? "checkmark.icloud" : "icloud.slash")
                            .font(.system(size: 29, weight: .regular))
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                            .frame(width: 50, height: 50)
                            .background(ATHLTHStudioStyle.canvas,
                                        in: RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(tr("Your training plans across devices",
                                    "Treningsplanene dine på tvers av enheter"))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(ATHLTHStudioStyle.ink)
                            Text(sync.enabled
                                ? tr("Optional plan sync is on", "Valgfri plansynkronisering er på")
                                : tr("Stored locally until you choose otherwise",
                                     "Lagres lokalt til du velger noe annet"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(tr(
                        "Only your saved training plans, including plan notes, are synchronized when you consent. Apple Health recordings, heart-rate samples, workout history and GPS routes are not uploaded by this feature.",
                        "Kun lagrede treningsplaner, inkludert plannotater, synkroniseres når du samtykker. Apple Health-målinger, pulsdata, treningshistorikk og GPS-ruter lastes ikke opp av denne funksjonen."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 11) {
                        if sync.enabled {
                            Button {
                                Task { await sync.sync(session: session) }
                            } label: {
                                Label(tr("Check for changes", "Se etter endringer"),
                                      systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHStudioStyle.ink)
                            .disabled(sync.isBusy)

                            Button(role: .destructive) {
                                showingDisableConfirmation = true
                            } label: {
                                Label(tr("Turn off", "Slå av"),
                                      systemImage: "icloud.slash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(sync.isBusy)
                        } else {
                            Button {
                                Task {
                                    await sync.setEnabled(true, session: session)
                                    if sync.enabled { await sync.sync(session: session) }
                                }
                            } label: {
                                Label(tr("Enable plan sync", "Aktiver plansynkronisering"),
                                      systemImage: "checkmark.icloud")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHStudioStyle.ink)
                            .disabled(sync.isBusy || !session.signedIn)
                        }
                        if sync.isBusy { ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !session.signedIn {
                        Label(tr("Sign in before enabling cross-device sync.",
                                 "Logg inn for å aktivere synkronisering mellom enheter."),
                              systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label(tr("Synchronization status", "Synkroniseringsstatus"),
                              systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(sync.status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let date = sync.lastSuccessfulSync {
                            Text(tr("Last successful check: ", "Sist kontrollert: ") +
                                 date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(17)
                    .background(ATHLTHStudioStyle.canvas,
                                in: RoundedRectangle(cornerRadius: 16))

                    if !sync.conflicts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(tr("Plans needing your decision",
                                     "Planer som krever ditt valg"),
                                  systemImage: "exclamationmark.triangle")
                                .font(.headline)
                                .foregroundStyle(ATHLTHStudioStyle.ink)

                            Text(tr("Conflicts are never overwritten automatically. Review each plan before choosing which copy to keep.",
                                    "Konflikter overskrives aldri automatisk. Gå gjennom hver plan før du velger hvilken kopi som skal beholdes."))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(sync.conflicts) { conflict in
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(conflict.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHStudioStyle.ink)
                                    HStack(spacing: 10) {
                                        Button(tr("Keep this device", "Behold denne enheten")) {
                                            pendingResolution = conflict
                                            preferCloud = false
                                        }
                                        Button(tr("Use cloud copy", "Bruk skykopien")) {
                                            pendingResolution = conflict
                                            preferCloud = true
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(sync.isBusy)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(ATHLTHStudioStyle.outline))
                            }
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHStudioStyle.paper.ignoresSafeArea())
            .navigationTitle(tr("Plan sync", "Plansynkronisering"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            tr("Stop plan sync and delete its cloud copies?",
               "Stoppe plansynkronisering og slette skykopiene?"),
            isPresented: $showingDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button(tr("Stop and delete cloud copies",
                      "Stopp og slett skykopiene"), role: .destructive) {
                Task { await sync.setEnabled(false, session: session) }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr("Plans saved on this device remain. If cloud deletion fails, the status will show what needs attention.",
                    "Planer på denne enheten beholdes. Hvis sletting i skyen mislykkes, viser statusen hva som må følges opp."))
        }
        .confirmationDialog(
            tr("Choose which version to keep?", "Velg hvilken versjon du vil beholde?"),
            isPresented: Binding(
                get: { pendingResolution != nil },
                set: { if !$0 { pendingResolution = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Confirm choice", "Bekreft valget")) {
                guard let conflict = pendingResolution else { return }
                let useCloud = preferCloud
                pendingResolution = nil
                Task {
                    await sync.resolve(
                        planID: conflict.id, preferRemote: useCloud,
                        session: session
                    )
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingResolution = nil
            }
        } message: {
            Text(preferCloud
                ? tr("Replace this device's plan with the cloud version.",
                     "Erstatt planen på denne enheten med skykopien.")
                : tr("Keep this device's plan instead of the cloud version.",
                     "Behold planen på denne enheten i stedet for skykopien."))
        }
    }
}
