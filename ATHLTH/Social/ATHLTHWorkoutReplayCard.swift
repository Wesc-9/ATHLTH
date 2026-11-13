import Foundation
import SwiftUI

/// Reject implausible speed and near-stationary outdoor sessions before
/// presenting pace trends, comparisons or achievement claims. No inferred
/// sleep, inactivity diagnoses, or automatic changes to Apple Health.
enum ATHLTHReplayDataQuality {
    static func needsReview(
        activity: WorkoutActivity,
        isIndoor: Bool?,
        duration: TimeInterval,
        distanceMeters: Double?
    ) -> Bool {
        guard isIndoor != true, duration.isFinite, duration >= 1_800,
              [.running, .walking, .hiking, .cycling].contains(activity),
              let distanceMeters, distanceMeters.isFinite,
              distanceMeters >= 0
        else { return false }

        // A recorded 6h45 run with 20m of movement must be flagged.
        return (duration >= 3_600 && distanceMeters < 150) ||
            (duration >= 1_800 && distanceMeters / duration < 0.10)
    }

    static func plausiblePace(
        _ secondsPerKilometer: Double,
        activity: WorkoutActivity
    ) -> Bool {
        guard secondsPerKilometer.isFinite else { return false }
        switch activity {
        case .running: return (120...1_500).contains(secondsPerKilometer)
        case .walking, .hiking: return (180...2_400).contains(secondsPerKilometer)
        case .cycling: return (55...1_200).contains(secondsPerKilometer)
        default: return false
        }
    }

    static func usablePace(
        duration: TimeInterval,
        distanceMeters: Double?,
        activity: WorkoutActivity,
        requiresReview: Bool
    ) -> Double? {
        guard !requiresReview, duration.isFinite, duration > 0,
              let distanceMeters, distanceMeters.isFinite,
              distanceMeters >= 500 else { return nil }
        let pace = duration / (distanceMeters / 1_000)
        return plausiblePace(pace, activity: activity) ? pace : nil
    }

    static func reliableSegment(
        distanceMeters: Double,
        paceSecondsPerKilometer: Double?,
        activity: WorkoutActivity
    ) -> Bool {
        guard distanceMeters.isFinite, distanceMeters >= 150,
              let paceSecondsPerKilometer else { return false }
        return plausiblePace(paceSecondsPerKilometer, activity: activity)
    }

    /// Distance matching keeps the comparison honest: a 1 km jog cannot
    /// silently become the benchmark for a 10 km run.
    static func isComparableDistance(
        current: Double,
        previous: Double
    ) -> Bool {
        guard current.isFinite, previous.isFinite,
              current >= 750, previous >= 750 else { return false }
        return abs(previous - current) / current <= 0.15
    }
}

struct ATHLTHWorkoutReplayCard: View {
    let workout: SocialPublishableWorkout
    let context: WorkoutAIInsightContext?
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthStore: StrengthWorkoutStore
    @State private var showingMoments = false
    @State private var showingDataReview = false
    @State private var userConfirmedUnusual = false
    @State private var showingAllStrengthExercises = false

    private var isStrength: Bool {
        workout.activity == .strength
    }

    private var requiresDataReview: Bool {
        ATHLTHReplayDataQuality.needsReview(
            activity: workout.activity,
            isIndoor: workout.isIndoor,
            duration: workout.duration,
            distanceMeters: workout.distanceMeters
        )
    }

    private var validOverallPace: Double? {
        ATHLTHReplayDataQuality.usablePace(
            duration: workout.duration,
            distanceMeters: workout.distanceMeters,
            activity: workout.activity,
            requiresReview: requiresDataReview
        )
    }

    private var usableSegments: [WorkoutRouteHealthSegment] {
        guard !requiresDataReview else { return [] }
        return context?.segments.filter {
            ATHLTHReplayDataQuality.reliableSegment(
                distanceMeters: $0.distanceMeters,
                paceSecondsPerKilometer: $0.paceSecondsPerKilometer,
                activity: workout.activity
            )
        } ?? []
    }

    private var confirmedReviewKey: String {
        "athlth.replay.reviewed.\(workout.id.uuidString)"
    }

    private var replayHeadline: String {
        if requiresDataReview {
            return ATHLTHLocalization.choose(
                english: "Unusual workout data",
                norwegian: "Uvanlige øktdata"
            )
        }
        return replayMoments.first?.title ??
            ATHLTHLocalization.choose(
                english: "Your workout, in brief",
                norwegian: "Økten din, kort fortalt"
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showingMoments.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Image(replayArtwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 126)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        Image(systemName: showingMoments ? "sparkles.rectangle.stack.fill" : "sparkles")
                            .font(.system(size: 41, weight: .ultraLight))
                            .foregroundStyle(.white)

                        VStack {
                            Spacer()
                            Text("ATHLTH")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(.white)
                                .padding(.bottom, 8)
                        }
                    }
                    .frame(width: 96, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top, spacing: 4) {
                            Text("ATHLTH Replay")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Spacer(minLength: 2)
                            Text(ATHLTHLocalization.choose(
                                english: "HIGHLIGHTS", norwegian: "HØYDEPUNKTER"
                            ))
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.05), in: Capsule())
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Text(replayHeadline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer(minLength: 5)

                        Rectangle()
                            .fill(ATHLTHTheme.divider.opacity(0.65))
                            .frame(height: 0.7)

                        HStack(spacing: 7) {
                            replayMetric(
                                title: isStrength
                                    ? ATHLTHLocalization.choose(english: "Exercises", norwegian: "Øvelser")
                                    : ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                                value: replayFirstMetric,
                                icon: isStrength ? "dumbbell.fill" : "point.topleft.down.curvedto.point.bottomright.up"
                            )
                            replayMetric(
                                title: isStrength
                                    ? (workout.strengthTotalVolumeKilograms == nil &&
                                       workout.strengthCardioDurationSeconds != nil
                                       ? ATHLTHLocalization.choose(english: "Cardio", norwegian: "Kondisjon")
                                       : ATHLTHLocalization.choose(english: "Volume", norwegian: "Volum"))
                                    : ATHLTHLocalization.choose(english: "Avg pace", norwegian: "Snitt-tempo"),
                                value: replaySecondMetric,
                                icon: isStrength ? "scalemass.fill" : "speedometer"
                            )
                            replayMetric(
                                title: ATHLTHLocalization.choose(english: "Total", norwegian: "Totaltid"),
                                value: durationText(workout.duration),
                                icon: "chart.bar.fill"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 126)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: showingMoments ? "Close workout replay highlights"
                    : "Open workout replay highlights",
                norwegian: showingMoments ? "Lukk øktens tilbakeblikk"
                    : "Vis øktens tilbakeblikk"
            ))

            if requiresDataReview {
                Button { showingDataReview = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: userConfirmedUnusual
                              ? "checkmark.shield" : "exclamationmark.triangle")
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(ATHLTHLocalization.choose(
                            english: userConfirmedUnusual
                                ? "Reviewed · performance claims remain hidden"
                                : "Unusual duration and movement · review",
                            norwegian: userConfirmedUnusual
                                ? "Gjennomgått · usikre prestasjonstall er fortsatt skjult"
                                : "Uvanlig varighet og bevegelse · gjennomgå"
                        ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: 42)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .accessibilityIdentifier("athlth-replay-review-unusual-data")
            }

            if showingMoments {
                Divider()
                    .padding(.top, 12)

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATHLTH Coach")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(coachSummary)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(
                    ATHLTHTheme.premiumGoldSoft.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .padding(.top, 10)
                .accessibilityIdentifier("athlth-replay-coach-summary")
                if isStrength,
                   let seconds = workout.strengthCardioDurationSeconds,
                   seconds > 0 {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Cardio within strength",
                                    norwegian: "Kondisjon i styrkeøkten"
                                ),
                                systemImage: "figure.run"
                            )
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Spacer()
                            Text(durationText(Double(seconds)))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        if let measured = workout.strengthCardioMeasuredMeters, measured > 0 {
                            Label(
                                String(format: "%.2f km · ", measured / 1000) +
                                ATHLTHLocalization.choose(
                                    english: "measured by Apple Watch",
                                    norwegian: "målt med Apple Watch"
                                ),
                                systemImage: "applewatch"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        }
                        if let estimate = workout.strengthCardioEstimatedMeters, estimate > 0 {
                            Label(
                                String(format: "%.2f km · ", estimate / 1000) +
                                ATHLTHLocalization.choose(
                                    english: "estimated from manually entered speed",
                                    norwegian: "estimert fra manuelt oppgitt fart"
                                ),
                                systemImage: "speedometer"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        if let pulse = workout.strengthWorkoutAverageHeartRateBPM,
                           pulse.isFinite, pulse > 0 {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Full workout average heart rate",
                                    norwegian: "Snittpuls for hele økten"
                                ) + String(format: " · %.0f bpm", pulse),
                                systemImage: "heart"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "Cardio warm-ups are not included in strength volume or personal records.",
                            norwegian: "Kondisjonsoppvarming teller ikke som styrkevolum eller personlig rekord."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ATHLTHPlanDesign.warmSurface,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                if isStrength,
                   let performed = workout.strengthPerformedExerciseSummaries,
                   !performed.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(ATHLTHLocalization.choose(
                            english: "Exercises performed",
                            norwegian: "Gjennomførte øvelser"
                        ))
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        ForEach(Array((showingAllStrengthExercises
                            ? performed
                            : Array(performed.prefix(3))).enumerated()), id: \.offset) {
                            index, detail in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .frame(width: 23, height: 23)
                                    .background(
                                        ATHLTHPlanDesign.selectedSurface,
                                        in: Circle()
                                    )
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if performed.count > 3 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingAllStrengthExercises.toggle()
                                }
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: showingAllStrengthExercises
                                            ? "Show fewer exercises" : "See all \(performed.count) exercises",
                                        norwegian: showingAllStrengthExercises
                                            ? "Vis færre øvelser" : "Se alle \(performed.count) øvelser"
                                    ),
                                    systemImage: showingAllStrengthExercises
                                        ? "chevron.up" : "chevron.down"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        ATHLTHPlanDesign.warmSurface,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                VStack(spacing: 0) {
                    ForEach(Array(replayMoments.enumerated()), id: \.offset) { index, moment in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: moment.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(moment.tint)
                                .frame(width: 32, height: 32)
                                .background(moment.tint.opacity(0.09), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(moment.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(moment.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)

                        if index < replayMoments.count - 1 {
                            Divider().padding(.leading, 43)
                        }
                    }
                }

                if !isStrength && usableSegments.isEmpty && !requiresDataReview {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "More replay detail appears with route or heart-rate samples.",
                            norwegian: "Flere Replay-detaljer vises når økten har rute- eller pulsdata."
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 0.9)
        }
        .sheet(isPresented: $showingDataReview) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Check the workout recording",
                            norwegian: "Kontroller øktregistreringen"
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.title3.weight(.semibold))

                    Text(ATHLTHLocalization.choose(
                        english: "The workout lasted \(durationText(workout.duration)), but very little movement was registered. This can happen if the session was left running or the distance data is missing. ATHLTH cannot tell which happened.",
                        norwegian: "Økten varte \(durationText(workout.duration)), men svært lite bevegelse ble registrert. Økten kan ha blitt stående på, eller distansedata kan mangle. ATHLTH vet ikke hva som skjedde."
                    ))
                    .font(.subheadline)

                    Text(ATHLTHLocalization.choose(
                        english: "We omit unreliable pace, effort rankings and finishing claims. Review the workout in Apple Health if its times or distance are incorrect. Confirming here does not modify Apple Health.",
                        norwegian: "Vi skjuler upålitelige tempo- og prestasjonspåstander. Kontroller treningsøkten i Apple Helse hvis tid eller distanse er feil. Bekreftelse her endrer ikke Apple Helse."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Button {
                        userConfirmedUnusual = true
                        UserDefaults.standard.set(true, forKey: confirmedReviewKey)
                        showingDataReview = false
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "The recording is correct",
                            norwegian: "Registreringen stemmer"
                        ), systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTrainDesign.bronze)

                    Spacer(minLength: 0)
                }
                .padding(22)
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Workout data", norwegian: "Øktdata"
                ))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Done", norwegian: "Ferdig"
                        )) { showingDataReview = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            userConfirmedUnusual = UserDefaults.standard.bool(
                forKey: confirmedReviewKey
            )
            // After a strength workout, the actual completed exercise list
            // should be immediately visible rather than hidden behind Replay.
            if isStrength, !(workout.strengthPerformedExerciseSummaries ?? []).isEmpty {
                showingMoments = true
            }
        }
    }

    private func replayMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(value)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
            }
            .font(.system(size: 12, weight: .bold))

            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var replayArtwork: String {
        if workout.isIndoor == true && workout.activity == .running {
            return "TreadmillRecentCardHero"
        }
        if isStrength { return "StrengthPostWorkoutHero" }
        return "GoalRunning"
    }

    private var replayFirstMetric: String {
        if isStrength {
            return workout.strengthExerciseCount.map(String.init) ?? "—"
        }
        guard let meters = workout.distanceMeters,
              meters.isFinite && meters > 0 else { return "—" }
        return String(format: "%.2f km", meters / 1_000)
    }

    private var replaySecondMetric: String {
        if isStrength {
            if let volume = workout.strengthTotalVolumeKilograms,
               volume.isFinite, volume > 0 {
                return volume >= 1_000
                    ? String(format: "%.1f t", volume / 1_000)
                    : String(format: "%.0f kg", volume)
            }
            if let seconds = workout.strengthCardioDurationSeconds {
                return durationText(Double(seconds))
            }
            return "—"
        }
        guard let meters = workout.distanceMeters,
              meters > 0 && workout.duration > 0 else { return "—" }
        return paceText(workout.duration / (meters / 1_000))
    }

    private var replayMoments: [ReplayMoment] {
        if isStrength {
            return strengthMoments
        }

        return enduranceMoments
    }

    private var strengthMoments: [ReplayMoment] {
        var moments: [ReplayMoment] = []

        if let groups = workout.strengthMuscleGroups,
           !groups.isEmpty {
            let names = groups.prefix(3).joined(separator: ", ")
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Training focus", norwegian: "Treningsfokus"),
                    detail: names,
                    icon: "figure.strengthtraining.traditional",
                    tint: ATHLTHTheme.vitality
                )
            )
        }

        if let volume = workout.strengthTotalVolumeKilograms,
           volume > 0 {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Total volume", norwegian: "Totalt volum"),
                    detail: formatWeight(volume),
                    icon: "sum",
                    tint: ATHLTHTheme.accent
                )
            )
        }

        if let heaviest = workout.strengthHeaviestWeightKilograms,
           heaviest > 0 {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Heaviest load", norwegian: "Tyngste løft"),
                    detail: formatWeight(heaviest),
                    icon: "dumbbell.fill",
                    tint: ATHLTHTheme.premiumGold
                )
            )
        }

        if let reps = workout.strengthTotalReps,
           reps > 0,
           moments.count < 3 {
            moments.append(
                ReplayMoment(
                    title: "Work completed",
                    detail: ATHLTHLocalization.choose(english: "\(reps) total reps", norwegian: "\(reps) repetisjoner totalt"),
                    icon: "repeat",
                    tint: .blue
                )
            )
        }

        if moments.isEmpty {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Session complete", norwegian: "Økt fullført"),
                    detail: durationText(workout.duration),
                    icon: "checkmark.circle.fill",
                    tint: ATHLTHTheme.vitality
                )
            )
        }

        return Array(moments.prefix(3))
    }

    private var enduranceMoments: [ReplayMoment] {
        var moments: [ReplayMoment] = []

        if let fastest = usableSegments
            .filter({ ($0.paceSecondsPerKilometer ?? 0) > 0 })
            .min(by: {
                ($0.paceSecondsPerKilometer ?? .greatestFiniteMagnitude) <
                ($1.paceSecondsPerKilometer ?? .greatestFiniteMagnitude)
            }),
           let pace = fastest.paceSecondsPerKilometer {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(
                        english: "Fastest phase · \(fastest.label)",
                        norwegian: "Raskeste fase · \(fastest.label)"
                    ),
                    detail: ATHLTHLocalization.choose(
                        english: "\(paceText(pace)) average pace",
                        norwegian: "\(paceText(pace)) snittempo"
                    ),
                    icon: "speedometer",
                    tint: ATHLTHTheme.vitality
                )
            )
        }

        if let peak = usableSegments
            .filter({ $0.maxHeartRateBPM != nil })
            .max(by: {
                ($0.maxHeartRateBPM ?? 0) <
                ($1.maxHeartRateBPM ?? 0)
            }),
           let maxHR = peak.maxHeartRateBPM {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(
                        english: "Highest effort · \(peak.label)",
                        norwegian: "Høyeste belastning · \(peak.label)"
                    ),
                    detail: ATHLTHLocalization.choose(
                        english: "Heart rate reached \(Int(maxHR.rounded())) bpm",
                        norwegian: "Pulsen nådde \(Int(maxHR.rounded())) slag/min"
                    ),
                    icon: "heart.fill",
                    tint: .red
                )
            )
        }

        if let opening = usableSegments.first?.paceSecondsPerKilometer,
           let finish = usableSegments.last?.paceSecondsPerKilometer,
           opening > 0,
           finish > 0 {
            let percent =
                ((opening - finish) / opening) * 100

            if abs(percent) >= 2 {
                moments.append(
                    ReplayMoment(
                        title:
                            percent > 0
                                ? ATHLTHLocalization.choose(english: "You finished stronger", norwegian: "Du avsluttet sterkere")
                                : ATHLTHLocalization.choose(english: "The finish got tougher", norwegian: "Avslutningen ble tyngre"),
                        detail:
                            percent > 0
                                ? ATHLTHLocalization.choose(
                                    english: "Final-phase pace was about \(Int(abs(percent).rounded()))% faster than the opening phase.",
                                    norwegian: "Tempoet mot slutten var omtrent \(Int(abs(percent).rounded())) % raskere enn i starten."
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Final-phase pace was about \(Int(abs(percent).rounded()))% slower than the opening phase.",
                                    norwegian: "Tempoet mot slutten var omtrent \(Int(abs(percent).rounded())) % saktere enn i starten."
                                ),
                        icon:
                            percent > 0
                                ? "arrow.up.forward.circle.fill"
                                : "arrow.down.forward.circle.fill",
                        tint:
                            percent > 0
                                ? ATHLTHTheme.accent
                                : .orange
                    )
                )
            }
        }

        if moments.count < 3,
           let distance = workout.distanceMeters,
           distance > 0 {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Distance covered", norwegian: "Tilbakelagt distanse"),
                    detail: String(
                        format: "%.2f km in %@",
                        distance / 1_000,
                        durationText(workout.duration)
                    ),
                    icon: activitySystemImage,
                    tint: ATHLTHTheme.accentDeep
                )
            )
        }

        if moments.count < 3,
           let calories = workout.activeEnergyKilocalories,
           calories > 0 {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Energy", norwegian: "Energi"),
                    detail: ATHLTHLocalization.choose(
                        english: "\(Int(calories.rounded())) active kcal",
                        norwegian: "\(Int(calories.rounded())) aktive kcal"
                    ),
                    icon: "flame.fill",
                    tint: .orange
                )
            )
        }

        if moments.isEmpty {
            moments.append(
                ReplayMoment(
                    title: ATHLTHLocalization.choose(english: "Workout complete", norwegian: "Økt fullført"),
                    detail: durationText(workout.duration),
                    icon: "checkmark.circle.fill",
                    tint: ATHLTHTheme.vitality
                )
            )
        }

        return Array(moments.prefix(3))
    }

    private var activitySystemImage: String {
        switch workout.activity {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .cycling:
            return "figure.outdoor.cycle"
        case .swimming:
            return "figure.pool.swim"
        case .hiking:
            return "figure.hiking"
        case .strength:
            return "dumbbell.fill"
        case .hiit:
            return "figure.highintensity.intervaltraining"
        case .rowing:
            return "figure.rower"
        case .elliptical:
            return "figure.elliptical"
        case .stairClimbing:
            return "figure.stair.stepper"
        case .yoga:
            return "figure.yoga"
        case .coreTraining:
            return "figure.core.training"
        case .other:
            return "figure.mixed.cardio"
        }
    }

    private func paceText(
        _ secondsPerKilometer: Double
    ) -> String {
        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let seconds =
            max(Int(secondsPerKilometer.rounded()), 0)
        let minutes = seconds / 60
        let remainder = seconds % 60

        return String(
            format: "%d:%02d /km",
            minutes,
            remainder
        )
    }

    private func durationText(
        _ duration: TimeInterval
    ) -> String {
        let totalSeconds =
            max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%dh %02dm",
                hours,
                minutes
            )
        }

        return String(
            format: "%dm %02ds",
            minutes,
            seconds
        )
    }

    private func formatWeight(
        _ kilograms: Double
    ) -> String {
        if kilograms >= 1_000 {
            return String(
                format: "%.1f t",
                kilograms / 1_000
            )
        }

        return String(
            format: "%.0f kg",
            kilograms
        )
    }
}

private struct ReplayMoment {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
}


extension HealthKitManager {
    func athlthReplayContext(
        for workout: SocialPublishableWorkout,
        maximumHeartRateBPM: Int?
    ) async -> WorkoutAIInsightContext? {
        guard workout.activity != .strength else {
            return nil
        }

        let summary: WorkoutSummary?

        if let current = workouts.first(
            where: { $0.id == workout.id }
        ) {
            summary = current
        } else {
            summary =
                (try? await workoutHistory())?
                    .first {
                        $0.id == workout.id
                    }
        }

        guard let summary else {
            return nil
        }

        return await workoutAIInsightContext(
            for: summary,
            maximumHeartRateBPM:
                maximumHeartRateBPM
        )
    }
}
