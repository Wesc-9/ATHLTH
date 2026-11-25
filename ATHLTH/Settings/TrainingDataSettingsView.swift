import SwiftUI

struct TrainingDataSettingsView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var backups: TrainingBackupStore
    @EnvironmentObject private var studioPlanSync: ATHLTHStudioPlanSyncStore
    @EnvironmentObject private var strengthAccountSync: ATHLTHStrengthAccountSyncStore
    @EnvironmentObject private var exercises: ExerciseLibraryStore
    @EnvironmentObject private var running: RunningWorkoutLibraryStore
    @EnvironmentObject private var phone: IPhoneWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var goalSync: ATHLTHGoalAccountSyncStore
    @EnvironmentObject private var audioSync: ATHLTHAudioCoachAccountSyncStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var syncing = false
    @State private var showingBackup = false
    @State private var showingDetails = false
    @State private var selectedBackup: TrainingBackupRow?
    @State private var legacyWatchResultToClaim: WatchWorkoutResult?
    @State private var confirmLegacy = false
    @State private var confirmDeleteBackups = false
    @State private var planConflictToResolve: ATHLTHStudioPlanSyncStore.Conflict?

    private var syncSection: some View {
        ATHLTHSettingsGroup(title: tr("Account sync", "Kontosynkronisering")) {
            PremiumSettingsCard {
                PremiumSettingsRow(icon: "icloud", iconTint: ATHLTHTheme.accentDeep,
                    iconBackground: ATHLTHTheme.premiumGoldSoft,
                    title: tr("Automatic synchronization", "Automatisk synkronisering"),
                    subtitle: session.signedIn ? tr("Part of your ATHLTH account", "En del av ATHLTH-kontoen din") :
                        tr("Sign in to synchronize", "Logg inn for å synkronisere")) {
                    if anySyncBusy { ProgressView().controlSize(.small) }
                }
                SettingsDivider()
                syncRow("calendar", tr("Training plans", "Treningsplaner"), studioPlanSync.status,
                        studioPlanSync.lastSuccessfulSync, studioPlanSync.isBusy)
                SettingsDivider()
                syncRow("dumbbell", tr("Strength history", "Styrkehistorikk"), strengthAccountSync.status,
                        strengthAccountSync.lastSuccessfulSync, strengthAccountSync.isBusy)
                SettingsDivider()
                syncRow("target", tr("Goals", "Mål"), goalSync.status, goalSync.lastSuccessfulSync, goalSync.isSyncing)
                SettingsDivider()
                syncRow("waveform", tr("Audio Coach templates", "Audio coach-maler"), audioSync.status,
                        audioSync.lastSuccessfulSync, audioSync.isBusy)
                if session.signedIn && !studioPlanSync.enabled {
                    detail(tr("A previous plan sync opt-out remains respected. Review it before continuing.", "Et tidligere fravalg av plansynkronisering er beholdt. Bekreft det før du fortsetter."))
                    Button(tr("Resume account plan sync", "Gjenoppta plansynkronisering")) {
                        Task { await studioPlanSync.acknowledgeLegacyOptOut(session: session) }
                    }.disabled(studioPlanSync.isBusy).padding(16)
                }
                if !studioPlanSync.conflicts.isEmpty {
                    detail(tr("Choose which plan version to keep. No conflict is overwritten automatically.", "Velg hvilken planversjon du vil beholde. Ingen konflikt overskrives automatisk."))
                    ForEach(studioPlanSync.conflicts) { conflict in
                        Button { planConflictToResolve = conflict } label: {
                            Label(conflict.title, systemImage: "exclamationmark.triangle").frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        }.buttonStyle(.plain)
                    }
                }
                SettingsDivider()
                Button {
                    Task { await syncNow() }
                } label: {
                    Label(tr("Sync now", "Synkroniser nå"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(16)
                }.buttonStyle(.plain).foregroundStyle(ATHLTHTheme.accentDeep)
                    .disabled(anySyncBusy || !session.signedIn)
            }
        }
    }

    private func syncRow(_ icon: String, _ title: String, _ status: String, _ last: Date?, _ busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PremiumSettingsRow(icon: icon, title: title, subtitle: busy ? tr("Synchronizing…", "Synkroniserer…") : status) {
                if busy { ProgressView().controlSize(.small) }
            }
            if let last {
                Text(tr("Last successful sync: ", "Sist vellykket: ") + last.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(ATHLTHTheme.mutedText).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    @MainActor private func syncNow() async {
        guard !anySyncBusy, session.signedIn else { return }
        let owner = session.profile.userID
        syncing = true
        defer { syncing = false }
        await studioPlanSync.sync(session: session)
        guard session.signedIn, session.profile.userID == owner else { return }
        await strengthAccountSync.sync(session: session, strength: strength, force: true)
        guard session.signedIn, session.profile.userID == owner else { return }
        await goalSync.sync(session: session, goals: goals)
        guard session.signedIn, session.profile.userID == owner else { return }
        await audioSync.sync(session: session, settings: settings)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }

    private var backupControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(tr("Extra cloud backup", "Ekstra sikkerhetskopi i skyen"),
                   isOn: Binding(get: { backups.enabled }, set: { value in Task { await backups.setEnabled(value) } }))
                .tint(ATHLTHTheme.premiumGold).disabled(backups.isBusy || !session.signedIn).padding(.horizontal, 16)
            detail(tr("Optional backup with Supabase for restoration. It may contain personal training data, goals and saved route locations. Imported health readings and recorded GPS traces are excluded. This is not live account sync.", "Frivillig sikkerhetskopi hos Supabase for gjenoppretting. Kan inneholde personlige treningsdata, mål og lagrede ruteposisjoner. Importerte helsemålinger og registrerte GPS-spor er utelatt. Dette er ikke løpende kontosynkronisering."))
            detail(backups.status)
            Button(tr("Back up now", "Sikkerhetskopier nå")) { Task { await backups.backUp(userID: session.profile.userID, force: true) } }
                .disabled(backups.isBusy || !session.signedIn || !backups.enabled).padding(.horizontal, 16)
            Button(tr("Find backups", "Finn sikkerhetskopier")) { Task { await backups.loadBackups(userID: session.profile.userID) } }
                .disabled(backups.isBusy || !session.signedIn).padding(.horizontal, 16)
            ForEach(backups.available) { backup in
                Button { selectedBackup = backup } label: {
                    VStack(alignment: .leading) {
                        Text(backup.updated_at.formatted(date: .abbreviated, time: .shortened))
                        Text(backup.device_id == backups.deviceID ? tr("This device", "Denne enheten") : tr("Other device", "Annen enhet")).font(.caption)
                    }
                }.disabled(!backups.enabled || !mayRestoreBackup).padding(.horizontal, 16)
            }
            if !mayRestoreBackup {
                detail(tr("Finish the active workout before restoring.", "Avslutt den aktive økten før gjenoppretting."))
            }
            Button(tr(tr("Delete cloud backups", "Slett sikkerhetskopier"), "Slett sikkerhetskopier"), role: .destructive) { confirmDeleteBackups = true }
                .disabled(backups.isBusy || !session.signedIn).padding(16)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var legacySection: some View {
        if session.signedIn {
            let pending = watchConnection.pendingWorkoutResults.filter { $0.accountOwnerID == nil }
            if !pending.isEmpty || goals.hasLegacyGoals || strength.hasLegacyHistory {
                ATHLTHSettingsGroup(title: tr("Older local data", "Eldre lokale data")) {
                    PremiumSettingsCard {
                        detail(tr("Only import data that belongs to your current account.", "Importer bare data som tilhører kontoen din."))
                        ForEach(pending, id: \.id) { result in
                            Button { legacyWatchResultToClaim = result } label: {
                                Label(result.kind.title + " · " + result.endedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "applewatch").padding(16)
                            }
                        }
                        if goals.hasLegacyGoals || strength.hasLegacyHistory {
                            Button(tr("Restore my older goals and workouts", "Gjenopprett mine eldre mål og økter")) { confirmLegacy = true }.padding(16)
                        }
                    }
                }
            }
        }
    }

    private var mayRestoreBackup: Bool {
        TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: phone.active != nil,
            strengthActive: strength.activeWorkout != nil,
            mirroredWatchActive: workoutMirroring.hasActiveMirroredWorkout,
            watchReportedActive: watchConnection.hasActiveWatchWorkout
        )
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var anySyncBusy: Bool {
        syncing || studioPlanSync.isBusy || strengthAccountSync.isBusy ||
            goalSync.isSyncing || audioSync.isBusy
    }

    var body: some View {
        ATHLTHSettingsScreen(title: tr("Training data & sync", "Treningsdata og synkronisering"),
                             subtitle: tr("Your training across your devices.", "Treningen din på tvers av enheter.")) {
            syncSection
            ATHLTHSettingsGroup(title: tr("Backup", "Sikkerhetskopier")) {
                PremiumSettingsCard {
                    DisclosureGroup(isExpanded: $showingBackup) {
                        backupControls
                    } label: {
                        PremiumSettingsRow(icon: "externaldrive.badge.icloud",
                            iconTint: ATHLTHTheme.accentDeep, iconBackground: ATHLTHTheme.premiumGoldSoft,
                            title: tr("Manage backups", "Administrer sikkerhetskopier"),
                            subtitle: backups.enabled ? tr("Extra backup enabled", "Ekstra sikkerhetskopi aktivert") :
                                tr("Optional recovery copies", "Frivillig sikkerhetskopiering")) { EmptyView() }
                    }
                    .tint(ATHLTHTheme.accentDeep)
                    .padding(.trailing, 12)
                }
            }
            ATHLTHSettingsGroup(title: tr("Privacy", "Personvern")) {
                PremiumSettingsCard {
                    NavigationLink { ATHLTHAccountAIConsentView() } label: {
                        PremiumSettingsRow(icon: "shield.lefthalf.filled", title: tr("AI & data consent", "AI og datasamtykker"),
                            subtitle: tr("Manage Coach sharing separately", "Administrer deling med Coach separat")) {
                            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }.buttonStyle(.plain)
                    SettingsDivider()
                    DisclosureGroup(isExpanded: $showingDetails) {
                        detail(tr("Account sync is private, not public sharing. Plan sync excludes private notes and raw Apple Health samples. Completed strength logs exclude raw heart rate, GPS and imported health metrics. Goal sync currently also includes manually entered body measurements. Extra backup and AI consent are separate.", "Kontosynkronisering er privat, ikke offentlig deling. Plansynk utelater private notater og rådata fra Apple Health. Styrkelogger utelater rå pulsdata, GPS og importerte helsemålinger. Målsynk inkluderer foreløpig også manuelt registrerte kroppsmål. Ekstra sikkerhetskopi og AI-samtykke er separate."))
                    } label: {
                        PremiumSettingsRow(icon: "info.circle", title: tr("About synchronization", "Om synkronisering")) { EmptyView() }
                    }.padding(.trailing, 12)
                    SettingsDivider()
                    NavigationLink { LegalDocumentView(kind: .privacy) } label: {
                        PremiumSettingsRow(icon: "lock.shield", title: tr("Privacy policy", "Personvernerklæring")) {
                            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }.buttonStyle(.plain)
                }
            }
            legacySection
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
        .confirmationDialog(tr("Delete all cloud backups for this account?", "Slette alle sikkerhetskopier for denne kontoen?"), isPresented: $confirmDeleteBackups, titleVisibility: .visible) {
            Button(tr("Delete cloud backups", "Slett sikkerhetskopier"), role: .destructive) { Task { await backups.deleteCloudBackups(userID: session.profile.userID) } }
        } message: {
            Text(tr("This turns off automatic backup. Training data on your phone stays unchanged.", "Dette slår av ekstra sikkerhetskopiering. Treningsdata på enheten beholdes."))
        }
        .confirmationDialog(tr("Restore older data to this account?", "Gjenopprette eldre data til denne kontoen?"), isPresented: $confirmLegacy, titleVisibility: .visible) {
            Button(tr("Restore my data", "Gjenopprett mine data")) { goals.restoreLegacyGoals(); strength.restoreLegacyHistory() }
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
        .confirmationDialog(tr("Replace this phone’s saved training data with the selected backup?", "Erstatte lagrede treningsdata på denne enheten med sikkerhetskopien?"), isPresented: Binding(get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }), titleVisibility: .visible) {
            Button(tr("Restore backup", "Gjenopprett sikkerhetskopi"), role: .destructive) {
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
            Text(tr("Your current data is backed up first, using the same exclusions for recorded GPS traces, imported health readings and local photos. These excluded items cannot be recovered from cloud backup. Account settings and Coach history permission stay unchanged.", "Dagens data sikkerhetskopieres først med samme unntak for GPS-spor, importerte helsemålinger og lokale bilder. Disse kan ikke gjenopprettes fra skybackup. Kontoinnstillinger og Coach-samtykke beholdes."))
        }
    }
}
