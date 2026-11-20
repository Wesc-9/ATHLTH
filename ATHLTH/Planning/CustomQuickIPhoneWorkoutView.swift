import SwiftUI

enum CustomIPhoneQuickWorkoutMode: Hashable {
    case timed
    case retrospective
}

struct CustomIPhoneQuickLaunch: Identifiable {
    let id = UUID()
    let configuration: CustomQuickWorkoutConfiguration
    let mode: CustomIPhoneQuickWorkoutMode
}

/// iPhone is a real timer here, but never a pretend GPS or HR sensor.
/// Retrospective workouts are separate, provenance-marked manual entries.
struct CustomQuickIPhoneWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let configuration: CustomQuickWorkoutConfiguration
    let mode: CustomIPhoneQuickWorkoutMode

    @State private var resumedAt: Date?
    @State private var accumulatedSeconds: TimeInterval = 0
    @State private var manualCaptureID: UUID?
    @State private var approvedTimeLimit: TimeInterval = 5 * 3600
    @State private var manualMinutes = 30
    @State private var workoutDate = Date()
    @State private var distanceText = ""
    @State private var effort = 0
    @State private var notes = ""
    @State private var showingDiscard = false
    @State private var savedRecord: CustomQuickWorkoutRecord?
    @State private var invalidInputMessage: String?

    private let ink = ATHLTHTheme.primaryText
    private let muted = ATHLTHTheme.mutedText
    private let accent = ATHLTHTheme.accentDeep

    private var isTimed: Bool { mode == .timed }
    private var evidence: CustomQuickWorkoutEvidence {
        isTimed ? .phoneTimer : .manual
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero

                    if let savedRecord {
                        savedSummary(savedRecord)
                    } else {
                        if isTimed { liveTimer }
                        else { retrospectiveTime }

                        manualMetrics

                        VStack(alignment: .leading, spacing: 7) {
                            Label(
                                tr("About this recording", "Om registreringen"),
                                systemImage: "checkmark.shield"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            Text(tr(
                                "ATHLTH stores this as a manual workout. Time is measured by the iPhone timer or entered by you. Distance and effort are not verified by GPS, Apple Watch or HealthKit.",
                                "ATHLTH lagrer dette som en manuelt registrert økt. Tiden måles med iPhone-tidtaker eller oppgis av deg. Distanse og innsats er ikke bekreftet av GPS, Apple Watch eller HealthKit."
                            ))
                            .font(.caption)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(ATHLTHTheme.accentSoft.opacity(0.60),
                                    in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20)
                .padding(.bottom, 110)
            }
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(
                isTimed ? tr("iPhone workout", "iPhone-økt")
                        : tr("Log a workout", "Registrer økt")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(savedRecord == nil
                            ? tr("Close", "Lukk")
                            : tr("Done", "Ferdig")) {
                        if savedRecord != nil { dismiss() }
                        else { showingDiscard = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if savedRecord == nil {
                    bottomBar
                } else {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(accent, in: RoundedRectangle(cornerRadius: 18))
                        .padding(20)
                        .background(.ultraThinMaterial)
                }
            }
            .alert(
                tr("Close without saving?", "Lukke uten å lagre?"),
                isPresented: $showingDiscard
            ) {
                Button(tr("Discard", "Forkast"), role: .destructive) {
                    if isTimed, let manualCaptureID {
                        guard ATHLTHManualTimedCapture.discard(
                            id: manualCaptureID,
                            userID: session.profile.userID
                        ) else {
                            invalidInputMessage = tr(
                                "Cannot discard the protected timer. Try again.",
                                "Kunne ikke forkaste den lagrede tidtakeren. Prøv igjen."
                            )
                            return
                        }
                    }
                    dismiss()
                }
                Button(tr("Keep workout", "Fortsett økten"), role: .cancel) {}
            } message: {
                Text(tr(
                    "Your workout has not been saved yet.",
                    "Økten er ikke lagret ennå."
                ))
            }
            .alert(tr("Cannot save workout", "Kan ikke lagre økten"),
                   isPresented: Binding(
                    get: { invalidInputMessage != nil },
                    set: { if !$0 { invalidInputMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(invalidInputMessage ?? "")
            }
            .onAppear {
                guard isTimed, savedRecord == nil,
                      manualCaptureID == nil else { return }
                do {
                    let snapshot = try ATHLTHManualTimedCapture.beginOrResume(
                        configuration: configuration,
                        userID: session.profile.userID
                    )
                    manualCaptureID = snapshot.id
                    accumulatedSeconds = snapshot.accumulatedSeconds
                    resumedAt = snapshot.resumedAt
                    approvedTimeLimit = snapshot.approvedTimeLimit
                    // A social lobby is confirmed only after a real protected
                    // timer exists. A failed admission never sends started.
                    if !configuration.selectedFriendIDs.isEmpty {
                        Task {
                            _ = await social.confirmCurrentJoinedWorkoutStarted()
                        }
                    }
                } catch {
                    invalidInputMessage = error.localizedDescription
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: configuration.activity.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 55, height: 55)
                .background(ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text(configuration.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ink)
                Label(
                    isTimed ? tr("iPhone measures time", "iPhone måler tiden")
                            : tr("Enter previous workout", "Etterregistrer økten"),
                    systemImage: "iphone"
                )
                .font(.caption)
                .foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 23))
    }

    private var liveTimer: some View {
        VStack(spacing: 13) {
            Text(tr("ELAPSED TIME", "MEDGÅTT TID"))
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(muted)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 9) {
                    Text(clockText(seconds: elapsed(at: context.date)))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    if elapsed(at: context.date) >= approvedTimeLimit {
                        Text(tr("Time limit reached · confirm to continue", "Tidsgrense nådd · bekreft for å fortsette"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Button(tr("Continue for one hour", "Fortsett én time til")) {
                            let now = Date()
                            guard let manualCaptureID else { return }
                            let seconds = elapsed(at: now)
                            let cap = min(24 * 3600, approvedTimeLimit + 3600)
                            if ATHLTHManualTimedCapture.update(
                                id: manualCaptureID, userID: session.profile.userID,
                                accumulatedSeconds: seconds, resumedAt: now,
                                approvedTimeLimit: cap
                            ) {
                                accumulatedSeconds = seconds
                                resumedAt = now
                                approvedTimeLimit = cap
                            } else {
                                invalidInputMessage = tr(
                                    "Cannot save the updated timer.",
                                    "Kunne ikke lagre den oppdaterte tidtakeren."
                                )
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    if let cue = intervalCue(at: context.date) {
                        Text(cue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(maxWidth: .infinity)
            }

        }
        .padding(23)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var retrospectiveTime: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading(tr("When did you train?", "Når trente du?"))
            DatePicker(
                tr("Workout date", "Dato for økten"),
                selection: $workoutDate,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .tint(accent)
            Stepper(
                tr("Duration: \(manualMinutes) min",
                   "Varighet: \(manualMinutes) min"),
                value: $manualMinutes,
                in: 1...720
            )
            .font(.subheadline.weight(.medium))
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
    }

    private var manualMetrics: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(tr("Manual details", "Manuelle opplysninger"))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(tr("Distance (optional)", "Distanse (valgfritt)"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(tr("MANUAL", "MANUELL"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(accent)
                }
                HStack(spacing: 7) {
                    TextField(tr("e.g. 5.2", "f.eks. 5,2"),
                              text: $distanceText)
                        .keyboardType(.decimalPad)
                    Text("km")
                        .foregroundStyle(muted)
                }
                .padding(13)
                .background(ATHLTHTheme.canvasTop,
                            in: RoundedRectangle(cornerRadius: 13))
            }

            HStack {
                Text(tr("How hard was it?", "Hvor hard var økten?"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("", selection: $effort) {
                    Text(tr("Not specified", "Ikke oppgitt")).tag(0)
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value) / 10").tag(value)
                    }
                }
                .tint(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Notes (optional)", "Notater (valgfritt)"))
                    .font(.subheadline.weight(.medium))
                TextField(
                    tr("How did it go?", "Hvordan gikk det?"),
                    text: $notes, axis: .vertical
                )
                .lineLimit(2...4)
                .padding(13)
                .background(ATHLTHTheme.canvasTop,
                            in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
    }


    /// The shared live dock delegates pause/resume to the ORIGINAL persisted
    /// iPhone timer; neither a second clock nor a HealthKit writer is created.
    private func toggleTimedPause() {
        guard isTimed, savedRecord == nil,
              let manualCaptureID else { return }
        let now = Date()
        let nextAccumulated = resumedAt != nil
            ? elapsed(at: now) : accumulatedSeconds
        let nextResumed: Date? = resumedAt != nil ? nil : now
        guard ATHLTHManualTimedCapture.update(
            id: manualCaptureID, userID: session.profile.userID,
            accumulatedSeconds: nextAccumulated, resumedAt: nextResumed,
            approvedTimeLimit: approvedTimeLimit
        ) else {
            invalidInputMessage = tr(
                "Cannot save pause/resume. Try again.",
                "Kunne ikke lagre pause eller fortsett. Prøv igjen."
            )
            return
        }
        accumulatedSeconds = nextAccumulated
        resumedAt = nextResumed
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isTimed {
            ATHLTHLiveWorkoutBottomDock(
                mode: .manualTimed(
                    ATHLTHWorkoutSportMode(category: configuration.activity.rawValue),
                    isPaused: resumedAt == nil
                ),
                subtitle: configuration.title,
                primaryDisabled: manualCaptureID == nil,
                secondaryDisabled: manualCaptureID == nil,
                onPrimary: save,
                onSecondary: toggleTimedPause
            ) {
                Label(
                    tr("iPhone timer · manual metrics",
                       "iPhone-tidtaker · manuelle målinger"),
                    systemImage: "iphone"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        } else {
        Button(action: save) {
            Label(
                isTimed ? tr("Finish and save", "Avslutt og lagre")
                        : tr("Save manual workout", "Lagre manuell økt"),
                systemImage: "checkmark"
            )
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(accent, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        }
    }

    private func savedSummary(_ record: CustomQuickWorkoutRecord) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(accent)
            Text(tr("Workout saved", "Økten er lagret"))
                .font(.title2.weight(.bold))
            Text(clockText(seconds: record.durationSeconds))
                .font(.title3.monospacedDigit())
            Label(record.evidence.label, systemImage: "info.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(muted)
            Text(tr(
                "No unverified data is treated as GPS, heart rate or verified workout performance.",
                "Ingen manuelle data behandles som GPS-, puls- eller kvalitetssikrede treningsmålinger."
            ))
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func save() {
        guard savedRecord == nil else { return }
        if isTimed && (manualCaptureID == nil ||
           ATHLTHManualTimedCapture.current(for: session.profile.userID)?.id
                != manualCaptureID) {
            invalidInputMessage = tr(
                "This timer is not the active workout. Restore it before saving.",
                "Denne tidtakeren er ikke den aktive økten. Gjenopprett den før lagring."
            )
            return
        }
        let raw = distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let distance = raw.isEmpty ? nil :
            Double(raw.replacingOccurrences(of: ",", with: "."))
        if !raw.isEmpty && distance == nil {
            invalidInputMessage = tr(
                "Enter a valid distance or leave it blank.",
                "Skriv inn en gyldig distanse, eller la feltet stå tomt."
            )
            return
        }
        let seconds = isTimed ? elapsed(at: Date()) : Double(manualMinutes * 60)
        if let distance, !CustomQuickWorkoutRecord.validDistance(
            distance, durationSeconds: seconds, activity: configuration.activity
        ) {
            let limit = CustomQuickWorkoutRecord.maximumRunningSpeedKilometersPerHour(for: seconds)
                * seconds / 3600
            invalidInputMessage = tr(
                "Distance exceeds the plausible limit for this duration (max \(String(format: "%.2f", limit)) km).",
                "Distansen overstiger rimelig grense for denne varigheten (maks \(String(format: "%.2f", limit)) km)."
            )
            return
        }
        guard let record = CustomQuickWorkoutRecord.make(
            configuration: configuration,
            recordedAt: isTimed ? Date() : workoutDate,
            durationSeconds: seconds,
            distanceKilometers: distance,
            perceivedEffort: effort == 0 ? nil : effort,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : notes,
            evidence: evidence,
            id: manualCaptureID ?? UUID()
        ) else {
            invalidInputMessage = tr(
                "Record at least one second and use a distance between 0 and 1,000 km.",
                "Registrer minst ett sekund og bruk distanse over 0 og maks 1 000 km."
            )
            return
        }
        guard CustomQuickWorkoutJournal.save(
            record, userID: session.profile.userID
        ) else {
            invalidInputMessage = tr(
                "Your workout could not be saved. It remains open for retry.",
                "Økten kunne ikke lagres. Den er fortsatt åpen for nytt forsøk."
            )
            return
        }
        if isTimed, let manualCaptureID,
           !ATHLTHManualTimedCapture.closeAfterSavedRecord(
                id: manualCaptureID, userID: session.profile.userID
           ) {
            invalidInputMessage = tr(
                "The workout was saved, but the active timer could not be closed. Retry Finish to release it.",
                "Økten ble lagret, men tidtakeren kunne ikke avsluttes. Prøv Avslutt på nytt."
            )
            return
        }
        accumulatedSeconds = seconds
        resumedAt = nil
        savedRecord = record
    }

    private func elapsed(at now: Date) -> TimeInterval {
        min(approvedTimeLimit, accumulatedSeconds + (resumedAt.map {
            max(0, now.timeIntervalSince($0))
        } ?? 0))
    }

    private func clockText(seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(
            format: "%02d:%02d:%02d",
            value / 3_600, (value % 3_600) / 60, value % 60
        )
    }

    private func intervalCue(at now: Date) -> String? {
        guard let timeline = ATHLTHCustomWorkoutTimeline.state(
            method: configuration.method,
            durationMinutes: configuration.durationMinutes,
            workSeconds: configuration.workSeconds,
            restSeconds: configuration.restSeconds,
            rounds: configuration.rounds,
            elapsedSeconds: elapsed(at: now),
            isPaused: resumedAt == nil
        ) else { return nil }

        switch configuration.method {
        case .intervals, .tabata:
            if timeline.intervalsComplete {
                return tr("Intervals complete", "Alle drag fullført")
            }
            let round = timeline.roundNumber ?? 1
            let isRest = timeline.inRestInterval
            return tr(
                "Round \(round)/\(configuration.rounds) · \(isRest ? "Rest" : "Work")",
                "Drag \(round)/\(configuration.rounds) · \(isRest ? "Pause" : "Jobb")"
            )
        case .emom:
            let minute = timeline.roundNumber ?? 1
            return tr("Minute \(minute) · EMOM", "Minutt \(minute) · EMOM")
        case .amrap, .forTime:
            let remaining = timeline.remainingSeconds ?? 0
            return tr(
                "Remaining \(clockText(seconds: remaining))",
                "Gjenstår \(clockText(seconds: remaining))"
            )
        case .open:
            return nil
        }
    }

    private func sectionHeading(_ value: String) -> some View {
        Text(value.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(muted)
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}
