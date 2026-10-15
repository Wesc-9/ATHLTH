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

    let configuration: CustomQuickWorkoutConfiguration
    let mode: CustomIPhoneQuickWorkoutMode

    @State private var resumedAt: Date?
    @State private var accumulatedSeconds: TimeInterval = 0
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
                if isTimed && resumedAt == nil && savedRecord == nil {
                    resumedAt = Date()
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
                    if let cue = intervalCue(at: context.date) {
                        Text(cue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                let now = Date()
                if resumedAt != nil {
                    accumulatedSeconds = elapsed(at: now)
                    resumedAt = nil
                } else {
                    resumedAt = now
                }
            } label: {
                Label(
                    resumedAt == nil ? tr("Resume", "Fortsett")
                                     : tr("Pause", "Pause"),
                    systemImage: resumedAt == nil ? "play.fill" : "pause.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(ATHLTHTheme.accentSoft,
                            in: Capsule())
            }
            .buttonStyle(.plain)
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

    private var bottomBar: some View {
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
        guard let record = CustomQuickWorkoutRecord.make(
            configuration: configuration,
            recordedAt: isTimed ? Date() : workoutDate,
            durationSeconds: seconds,
            distanceKilometers: distance,
            perceivedEffort: effort == 0 ? nil : effort,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : notes,
            evidence: evidence
        ) else {
            invalidInputMessage = tr(
                "Record at least one second and use a distance between 0 and 1,000 km.",
                "Registrer minst ett sekund og bruk distanse over 0 og maks 1 000 km."
            )
            return
        }
        CustomQuickWorkoutJournal.save(record, userID: session.profile.userID)
        accumulatedSeconds = seconds
        resumedAt = nil
        savedRecord = record
    }

    private func elapsed(at now: Date) -> TimeInterval {
        accumulatedSeconds + (resumedAt.map {
            max(0, now.timeIntervalSince($0))
        } ?? 0)
    }

    private func clockText(seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(
            format: "%02d:%02d:%02d",
            value / 3_600, (value % 3_600) / 60, value % 60
        )
    }

    private func intervalCue(at now: Date) -> String? {
        let time = Int(elapsed(at: now))
        switch configuration.method {
        case .intervals, .tabata:
            let work = configuration.method == .tabata
                ? 20 : configuration.workSeconds
            let rest = configuration.method == .tabata
                ? 10 : configuration.restSeconds
            let cycle = max(1, work + rest)
            let round = min(time / cycle + 1, configuration.rounds)
            if time >= configuration.rounds * work +
                max(0, configuration.rounds - 1) * rest {
                return tr("Intervals complete", "Alle drag fullført")
            }
            let offset = time % cycle
            let isWorking = offset < work
            return tr(
                "Round \(round)/\(configuration.rounds) · \(isWorking ? "Work" : "Rest")",
                "Drag \(round)/\(configuration.rounds) · \(isWorking ? "Jobb" : "Pause")"
            )
        case .emom:
            return tr(
                "Minute \(time / 60 + 1) · EMOM",
                "Minutt \(time / 60 + 1) · EMOM"
            )
        case .amrap, .forTime:
            let remaining = max(0, configuration.durationMinutes * 60 - time)
            return tr("Remaining \(clockText(seconds: Double(remaining)))",
                      "Gjenstår \(clockText(seconds: Double(remaining)))")
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
