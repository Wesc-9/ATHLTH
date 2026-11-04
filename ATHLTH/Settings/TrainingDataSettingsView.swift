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
    @State private var consent = false
    @State private var selectedBackup: TrainingBackupRow?
    @State private var confirmLegacy = false
    @State private var confirmDeleteBackups = false
    @State private var planConflictToResolve: ATHLTHStudioPlanSyncStore.Conflict?

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
                    }.disabled(!backups.enabled || strength.activeWorkout != nil || phone.active != nil)
                }
                if strength.activeWorkout != nil || phone.active != nil {
                    Text("Finish your active workout before restoring a backup.").font(.footnote)
                }
            }
            Section(ATHLTHLocalization.choose(
                english: "Plan sync between devices",
                norwegian: "Plansynkronisering mellom enheter"
            )) {
                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Sync my training plans with other ATHLTH devices",
                        norwegian: "Synkroniser treningsplaner mellom ATHLTH-enheter"
                    ),
                    isOn: Binding(
                        get: { studioPlanSync.enabled },
                        set: { newValue in
                            Task {
                                await studioPlanSync.setEnabled(newValue, session: session)
                            }
                        }
                    )
                )
                .disabled(studioPlanSync.isBusy || !session.signedIn)
                Text(ATHLTHLocalization.choose(
                    english: "Optional and off by default. When enabled, your saved plans can be stored with ATHLTH’s cloud provider (Supabase), including manually entered notes, injuries and planned places. Completed workouts, Apple Health readings, GPS traces and readiness scores are never included. Enable it separately on each device. Disabling attempts to delete remote plan copies; local plans remain.",
                    norwegian: "Valgfritt og av som standard. Når du aktiverer dette, kan lagrede treningsplaner lagres hos ATHLTHs skyleverandør (Supabase), inkludert egne notater, eventuelle skader og planlagte steder. Gjennomførte økter, Apple Health-data, GPS-spor og restitusjonsscore inngår aldri. Aktiver separat på hver enhet. Ved deaktivering forsøkes sky-kopiene slettet; lokale planer beholdes."
                ))
                .font(.footnote)

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
        .confirmationDialog("Replace this phone’s saved training data with the selected backup?", isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }), titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                guard let backup = selectedBackup else { return }
                Task {
                    if await backups.restore(backup, userID: session.profile.userID) {
                        session.reloadTrainingContent()
                        phone.switchAccount(nil); phone.switchAccount(session.profile.userID)
                        goals.switchAccount(nil); goals.switchAccount(session.profile.userID)
                        strength.switchAccount(nil); strength.switchAccount(session.profile.userID)
                        exercises.switchAccount(nil); exercises.switchAccount(session.profile.userID)
                        running.switchAccount(nil); running.switchAccount(session.profile.userID)
                    }
                }
            }
        } message: {
            Text("Your current data is backed up first, using the same exclusions for recorded GPS traces, imported health readings and local photos. These excluded items cannot be recovered from cloud backup. Account settings and Coach history permission stay unchanged.")
        }
    }
}
