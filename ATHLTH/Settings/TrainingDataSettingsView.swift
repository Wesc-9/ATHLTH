import SwiftUI

struct TrainingDataSettingsView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var backups: TrainingBackupStore
    @EnvironmentObject private var studioPlanSync: ATHLTHStudioPlanSyncStore
    @EnvironmentObject private var exercises: ExerciseLibraryStore
    @EnvironmentObject private var running: RunningWorkoutLibraryStore
    @EnvironmentObject private var phone: IPhoneWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @State private var consent = false
    @State private var selectedBackup: TrainingBackupRow?
    @State private var legacyWatchResultToClaim: WatchWorkoutResult?
    @State private var confirmLegacy = false
    @State private var confirmDeleteBackups = false
    @State private var planConflictToResolve: ATHLTHStudioPlanSyncStore.Conflict?

    private var mayRestoreBackup: Bool {
        TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: phone.active != nil,
            strengthActive: strength.activeWorkout != nil,
            mirroredWatchActive: workoutMirroring.hasActiveMirroredWorkout,
            watchReportedActive: watchConnection.hasActiveWatchWorkout
        )
    }

    // Isolated from the main Form to avoid SwiftUI type-checker blowups.
    // All binding and conflict-handling behavior remains unchanged.
    private var planSyncSection: some View {
    Section(ATHLTHLocalization.choose(
        english: "Plan sync between devices",
        norwegian: "Plansynkronisering mellom enheter"
    )) {
        Text(ATHLTHLocalization.choose(
            english: "Signed-in training plans sync privately across your ATHLTH devices. This service does not upload Apple Health readings, recorded workouts or GPS traces. Plan notes may contain personal information.",
            norwegian: "Treningsplaner synkroniseres privat mellom ATHLTH-enheter når du er logget inn. Tjenesten laster ikke opp Apple Health-målinger, gjennomførte økter eller GPS-spor. Plannotater kan inneholde personopplysninger."
        ))
        .font(.footnote)
        if session.signedIn && !studioPlanSync.enabled {
            Button {
                Task { await studioPlanSync.acknowledgeLegacyOptOut(session: session) }
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Use account synchronization",
                    norwegian: "Bruk kontosynkronisering"
                ), systemImage: "checkmark.icloud")
            }
            .disabled(studioPlanSync.isBusy)
        }
        Text(studioPlanSync.status)
            .font(.footnote)
        if let updated = studioPlanSync.lastSuccessfulSync {
            Text(ATHLTHLocalization.choose(
                english: "Last checked: \(updated.formatted(date: .abbreviated, time: .shortened))",
                norwegian: "Sist kontrollert: \(updated.formatted(date: .abbreviated, time: .shortened))"
            ))
            .font(.caption).foregroundStyle(.secondary)
        }
        Button {
            Task { await studioPlanSync.sync(session: session) }
        } label: {
            Label(ATHLTHLocalization.choose(
                english: "Sync plans now", norwegian: "Synkroniser planer nå"
            ), systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!studioPlanSync.enabled || studioPlanSync.isBusy)
    
        if !studioPlanSync.conflicts.isEmpty {
            Text(ATHLTHLocalization.choose(
                english: "Different versions were found. Decide which copy to keep; neither will be overwritten automatically.",
                norwegian: "Ulike versjoner er funnet. Velg hvilken kopi du vil beholde; ingen overskrives automatisk."
            ))
            .font(.footnote)
            ForEach(studioPlanSync.conflicts) { conflict in
                Button {
                    planConflictToResolve = conflict
                } label: {
                    Label(conflict.title, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
            }
        }
    }
    }

    var body: some View {
        Form {
            Section("ATHLTH Coach") {
                Toggle("Share training history with Coach", isOn: $consent)
                    .onChange(of: consent) { _, enabled in
                        guard session.signedIn else { return }
                        AccountLocalStorage.write(enabled, name: "coachHistoryConsent", userID: session.profile.userID)
                    }
                Text("When enabled, a summary of up to the last 28 days of workouts is sent to Groq when you ask Coach to build or adapt a plan. Routes, sleep, heart rate and other raw health data are not included. Turn this off to stop sharing in future requests.")
                    .font(.footnote)
            }
            Section("Cloud backup") {
                Toggle("Allow cloud backup of my training data", isOn: Binding(get: { backups.enabled }, set: { value in Task { await backups.setEnabled(value) } }))
                    .disabled(backups.isBusy || !session.signedIn)
                Text("Optional. By enabling this, you agree to store the training data described below with ATHLTH’s cloud provider, Supabase, for backup and restoration. Goals and workout records can reveal health information. You can turn this off and delete your cloud copies at any time.")
                    .font(.footnote)
                NavigationLink("Privacy Policy") { LegalDocumentView(kind: .privacy) }
                Text(backups.status)
                Text("When enabled, automatic backup follows your ATHLTH account. It includes plans, saved routes, goals, exercise libraries, Coach preferences and completed strength logs and iPhone workout summaries. Imported pulse/calorie readings, recorded GPS traces, the Apple Health library, health-profile details and local photos are not copied. Planned saved routes do contain location data. Each phone keeps a separate backup. This is backup, not live two-way sync.")
                    .font(.footnote)
                Button("Back up now") { Task { await backups.backUp(userID: session.profile.userID, force: true) } }
                    .disabled(backups.isBusy || !session.signedIn || !backups.enabled)
                Button("Stop backup on all devices") { Task { await backups.setEnabled(false) } }
                    .disabled(backups.isBusy || !session.signedIn)
                Button("Find cloud backups") { Task { await backups.loadBackups(userID: session.profile.userID) } }
                    .disabled(backups.isBusy || !session.signedIn)
                Button("Delete cloud backups", role: .destructive) { confirmDeleteBackups = true }
                    .disabled(backups.isBusy || !session.signedIn)
                ForEach(backups.available) { backup in
                    Button {
                        selectedBackup = backup
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Backup · \(backup.updated_at.formatted(date: .abbreviated, time: .shortened))")
                            Text(backup.device_id == backups.deviceID ? "This phone" : "Another phone").font(.caption)
                        }
                    }.disabled(!backups.enabled || !mayRestoreBackup)
                }
                if !mayRestoreBackup {
                    Text(ATHLTHLocalization.choose(
                        english: "Finish the active iPhone or Apple Watch workout before restoring a backup.",
                        norwegian: "Avslutt den aktive økten på iPhone eller Apple Watch før du gjenoppretter en sikkerhetskopi."
                    ))
                    .font(.footnote)
                }
            }
            if session.signedIn {
                let legacyWatchResults = watchConnection.pendingWorkoutResults
                    .filter { $0.accountOwnerID == nil }
                if !legacyWatchResults.isEmpty {
                    Section(ATHLTHLocalization.choose(
                        english: "Older Apple Watch workouts",
                        norwegian: "Eldre Apple Watch-økter"
                    )) {
                        Text(ATHLTHLocalization.choose(
                            english: "These completed workouts were received without an ATHLTH account ID. They were not assigned automatically. Only claim workouts that belong to your current account.",
                            norwegian: "Disse fullførte øktene kom uten ATHLTH-konto-ID og er ikke tilordnet automatisk. Bekreft bare økter som tilhører kontoen du er logget inn på."
                        ))
                        .font(.footnote)

                        ForEach(legacyWatchResults, id: \.id) { result in
                            Button {
                                legacyWatchResultToClaim = result
                            } label: {
                                Label(
                                    "\(result.kind.title) · \(result.endedAt.formatted(date: .abbreviated, time: .shortened))",
                                    systemImage: "applewatch"
                                )
                            }
                        }
                    }
                }
            }
            planSyncSection
            if goals.hasLegacyGoals || strength.hasLegacyHistory {
                Section("Older data on this phone") {
                    Text("Older goals and strength logs have no recorded account owner. Restore them only if they belong to you.")
                    Button("These are my goals and workouts — restore") { confirmLegacy = true }
                }
            }
        }
        .athlthBrandedForm()
        .navigationTitle("Training data & Coach")
        .task(id: session.profile.userID) {
            consent = AccountLocalStorage.read(Bool.self, name: "coachHistoryConsent", userID: session.profile.userID) ?? false
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Resolve training plan difference",
                norwegian: "Velg hvilken treningsplan som skal beholdes"
            ),
            isPresented: Binding(
                get: { planConflictToResolve != nil },
                set: { if !$0 { planConflictToResolve = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Keep this device's version",
                norwegian: "Behold versjonen på denne enheten"
            )) {
                guard let selected = planConflictToResolve else { return }
                planConflictToResolve = nil
                Task {
                    await studioPlanSync.resolve(
                        planID: selected.id, preferRemote: false, session: session
                    )
                }
            }
            Button(ATHLTHLocalization.choose(
                english: "Use the cloud version",
                norwegian: "Bruk versjonen fra skyen"
            ), role: .destructive) {
                guard let selected = planConflictToResolve else { return }
                planConflictToResolve = nil
                Task {
                    await studioPlanSync.resolve(
                        planID: selected.id, preferRemote: true, session: session
                    )
                }
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Only your selected training plan is affected. Other plans and recorded workout results are preserved.",
                norwegian: "Kun den valgte treningsplanen påvirkes. Andre planer og registrerte treningsresultater beholdes."
            ))
        }
        .confirmationDialog("Delete all cloud backups for this account?", isPresented: $confirmDeleteBackups, titleVisibility: .visible) {
            Button("Delete cloud backups", role: .destructive) { Task { await backups.deleteCloudBackups(userID: session.profile.userID) } }
        } message: {
            Text("This turns off automatic backup. Training data on your phone stays unchanged.")
        }
        .confirmationDialog("Restore older data to this account?", isPresented: $confirmLegacy, titleVisibility: .visible) {
            Button("Restore my data") { goals.restoreLegacyGoals(); strength.restoreLegacyHistory() }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Import this older Watch workout to your current account?",
                norwegian: "Importer denne eldre Watch-økten til kontoen du bruker nå?"
            ),
            isPresented: Binding(
                get: { legacyWatchResultToClaim != nil },
                set: { if !$0 { legacyWatchResultToClaim = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Yes, this workout is mine",
                norwegian: "Ja, denne økten er min"
            )) {
                guard session.signedIn,
                      let result = legacyWatchResultToClaim else { return }
                legacyWatchResultToClaim = nil
                _ = watchConnection.claimLegacyCompletedWorkout(
                    result.id, for: session.profile.userID
                )
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Only confirm a workout you recorded. Watch results already linked to a different account cannot be reassigned.",
                norwegian: "Bekreft bare en økt du selv har registrert. Watch-økter som allerede er knyttet til en annen konto, kan ikke flyttes."
            ))
        }
        .confirmationDialog("Replace this phone’s saved training data with the selected backup?", isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }), titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                guard let backup = selectedBackup,
                      session.signedIn,
                      backup.user_id == session.profile.userID,
                      mayRestoreBackup else { return }
                let ownerID = session.profile.userID
                Task {
                    // Re-check immediately before async restore: an active
                    // Watch workout may have started while the dialog was open.
                    guard session.signedIn,
                          session.profile.userID == ownerID,
                          mayRestoreBackup else { return }
                    if await backups.restore(
                        backup,
                        userID: ownerID,
                        canApply: { mayRestoreBackup }
                    ) {
                        guard session.signedIn,
                              session.profile.userID == ownerID else { return }
                        // All cached stores must see the restored snapshot now,
                        // not only after the next cold launch.
                        session.reloadTrainingContent()
                        phone.switchAccount(nil); phone.switchAccount(ownerID)
                        goals.switchAccount(nil); goals.switchAccount(ownerID)
                        strength.switchAccount(nil); strength.switchAccount(ownerID)
                        exercises.switchAccount(nil); exercises.switchAccount(ownerID)
                        running.switchAccount(nil); running.switchAccount(ownerID)
                    }
                }
            }
            .disabled(!mayRestoreBackup)
        } message: {
            Text("Your current data is backed up first, using the same exclusions for recorded GPS traces, imported health readings and local photos. These excluded items cannot be recovered from cloud backup. Account settings and Coach history permission stay unchanged.")
        }
    }
}
