import SwiftUI
import UIKit
import AVKit

/// A foreground iPad can show one workout in several Stage Manager windows.
/// UIKit's idle-timer flag belongs to the whole app, not to the view. Only
/// the final active lease may restore its original state.
struct ATHLTHiPadKeepAwakeLeaseState {
    private(set) var activeWindowIDs: Set<UUID> = []
    private(set) var originalIdleTimerDisabled: Bool?

    mutating func setEnabled(
        _ enabled: Bool,
        for windowID: UUID,
        currentIdleTimerDisabled: Bool
    ) -> Bool? {
        if enabled {
            if activeWindowIDs.isEmpty {
                originalIdleTimerDisabled = currentIdleTimerDisabled
            }
            activeWindowIDs.insert(windowID)
            return true
        }
        guard activeWindowIDs.remove(windowID) != nil else { return nil }
        guard activeWindowIDs.isEmpty else { return true }
        let original = originalIdleTimerDisabled ?? false
        originalIdleTimerDisabled = nil
        return original
    }
}

@MainActor
enum ATHLTHiPadKeepAwakeCoordinator {
    private static var leases = ATHLTHiPadKeepAwakeLeaseState()

    static func setEnabled(_ enabled: Bool, for windowID: UUID) {
        if let next = leases.setEnabled(
            enabled, for: windowID,
            currentIdleTimerDisabled: UIApplication.shared.isIdleTimerDisabled
        ) {
            UIApplication.shared.isIdleTimerDisabled = next
        }
    }
}

/// iPad companion for an iPhone/Apple Watch workout. Gym Mode is only
/// a presentation of the same snapshot and source-authorized controls.
struct ATHLTHiPadLiveWorkoutView: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let onMinimize: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("athlth_ipad_live_keep_awake") private var keepAwake = false
    @State private var keepAwakeWindowID = UUID()
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var liveSharing: ATHLTHCrossDeviceWorkoutStore
    @State private var confirmingRemoteEnd = false
    @State private var gymMode = false
    private var screenAwake: Bool { (keepAwake || gymMode) && scenePhase == .active }

    private var liveMaximumBPM: Double? {
        snapshot.maximumHeartRateBPM ??
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: session.onboardingProfile?.maximumHeartRateBPM,
                dateOfBirth: session.onboardingProfile?.dateOfBirth,
                usesFemaleEstimate: session.onboardingProfile?.healthSex == .female
            )
    }

    private var measuredZone: Int? {
        ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: snapshot.heartRateBPM, maximumBPM: liveMaximumBPM
        )
    }

    private var runningPulseZones: some View {
        ATHLTHRunningPulseZoneGauge(
            heartRateBPM: snapshot.heartRateBPM,
            maximumHeartRateBPM: liveMaximumBPM,
            targetHeartRateZone: snapshot.targetHeartRateZone,
            targetMinimumBPM: snapshot.targetHeartRateMinimumBPM,
            targetMaximumBPM: snapshot.targetHeartRateMaximumBPM,
            targetPercentMin: snapshot.targetHeartRatePercentMin,
            targetPercentMax: snapshot.targetHeartRatePercentMax
        )
    }

    private let ink = ATHLTHPlanDesign.ink
    private let secondary = ATHLTHPlanDesign.secondaryInk
    private let bronze = ATHLTHPlanDesign.accentInk
    private let surface = ATHLTHPlanDesign.surface
    private let pale = ATHLTHPlanDesign.selectedSurface

    private var isStrength: Bool { snapshot.kind == "strength" }
    private var isCardio: Bool {
        ATHLTHSpectatorSportMetricPolicy.showsHeartRateZones(snapshot.kind)
    }
    private var isPaceSport: Bool {
        ATHLTHSpectatorSportMetricPolicy.supportsRunningPace(snapshot.kind)
    }
    private var hasDistanceMetric: Bool {
        ATHLTHSpectatorSportMetricPolicy.supportsDistance(snapshot.kind)
    }
    private var isWatch: Bool { snapshot.sourceDevice == "watch" }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 840 && !dynamicTypeSize.isAccessibilitySize
            let threeColumns = geometry.size.width >= 1160 && !dynamicTypeSize.isAccessibilitySize

            if gymMode {
                gymScreen
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    topBar(compact: geometry.size.width < 880 || dynamicTypeSize.isAccessibilitySize)

                    identity
                        .padding(.top, 4)

                    TrainTogetherStatusStrip()
                    remoteControlPanel

                    if threeColumns {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) {
                                if isStrength {
                                    ATHLTHiPadLiveStrengthDetailsPanel(snapshot: snapshot)
                                } else {
                                    ATHLTHiPadLiveTimelinePanel(snapshot: snapshot)
                                }
                                if isStrength { strengthProgress }
                                else { workoutProgress }
                            }
                            .frame(width: min(310, geometry.size.width * 0.24), alignment: .topLeading)

                            VStack(spacing: 16) {
                                activeStepCard
                                ATHLTHiPadLiveGhostDuelPanel(snapshot: snapshot)
                                if isPaceSport || ATHLTHWorkoutSportMode(category: snapshot.kind) == .cycling {
                                    ATHLTHiPadLiveGPSMap(snapshot: snapshot)
                                }
                                ATHLTHiPadLiveRouteProgressPanel(snapshot: snapshot)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            VStack(spacing: 16) {
                                elapsedHero
                                metrics
                                if snapshot.kind == "running" || snapshot.kind == "walking" {
                                    runningPulseZones
                                }
                                ATHLTHiPadLiveWorkoutExtrasPanel(snapshot: snapshot)
                                additionalDetails
                            }
                            .frame(width: min(370, geometry.size.width * 0.29), alignment: .topLeading)
                        }
                    } else if wide {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) {
                                elapsedHero
                                metrics
                                if snapshot.kind == "running" ||
                                   snapshot.kind == "walking" {
                                    runningPulseZones
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            VStack(spacing: 20) {
                                activeStepCard
                                if isStrength {
                                    strengthProgress
                                } else {
                                    workoutProgress
                                }
                                if isStrength {
                                    ATHLTHiPadLiveStrengthDetailsPanel(snapshot: snapshot)
                                } else {
                                    ATHLTHiPadLiveTimelinePanel(snapshot: snapshot)
                                }
                                ATHLTHiPadLiveGhostDuelPanel(snapshot: snapshot)
                                if isPaceSport || ATHLTHWorkoutSportMode(
                                    category: snapshot.kind
                                ) == .cycling {
                                    ATHLTHiPadLiveGPSMap(snapshot: snapshot)
                                }
                                ATHLTHiPadLiveRouteProgressPanel(snapshot: snapshot)
                                ATHLTHiPadLiveWorkoutExtrasPanel(snapshot: snapshot)
                                additionalDetails
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        elapsedHero
                        metrics
                        if snapshot.kind == "running" ||
                           snapshot.kind == "walking" {
                            runningPulseZones
                        }
                        activeStepCard
                        if isStrength {
                            strengthProgress
                        } else {
                            workoutProgress
                        }
                        if isStrength {
                            ATHLTHiPadLiveStrengthDetailsPanel(snapshot: snapshot)
                        } else {
                            ATHLTHiPadLiveTimelinePanel(snapshot: snapshot)
                        }
                        ATHLTHiPadLiveGhostDuelPanel(snapshot: snapshot)
                        if isPaceSport || ATHLTHWorkoutSportMode(
                            category: snapshot.kind
                        ) == .cycling {
                            ATHLTHiPadLiveGPSMap(snapshot: snapshot)
                        }
                        ATHLTHiPadLiveRouteProgressPanel(snapshot: snapshot)
                        ATHLTHiPadLiveWorkoutExtrasPanel(snapshot: snapshot)
                        additionalDetails
                    }

                    Label(
                        tr(
                            "The original device stays responsible for recording. Remote controls require separate permission.",
                            "Den opprinnelige enheten har ansvaret for opptaket. Fjernstyring krever egen tillatelse."
                        ),
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, wide ? 32 : 18)
                .padding(.top, 22)
                .padding(.bottom, 36)
                .frame(maxWidth: 1370)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
            }
        }
        .accessibilityIdentifier("athlth-ipad-live-workout-fullscreen")
        .confirmationDialog(
            tr("End this workout?", "Avslutte denne økten?"),
            isPresented: $confirmingRemoteEnd, titleVisibility: .visible
        ) {
            Button(tr("End workout", "Avslutt økt"), role: .destructive) {
                sendRemoteAction(.end)
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr("The original recording device will finish and save this workout.",
                    "Den opprinnelige treningsenheten avslutter og lagrer økten."))
        }
        .onAppear {
            ATHLTHiPadKeepAwakeCoordinator.setEnabled(
                screenAwake, for: keepAwakeWindowID
            )
        }
        .onChange(of: screenAwake) { _, enabled in
            ATHLTHiPadKeepAwakeCoordinator.setEnabled(enabled, for: keepAwakeWindowID)
        }
        .onDisappear {
            ATHLTHiPadKeepAwakeCoordinator.setEnabled(
                false, for: keepAwakeWindowID
            )
        }
    }

    private var gymScreen: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Label("GYM MODE", systemImage: "display")
                        .font(.caption.weight(.bold)).tracking(2)
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { gymMode = false }
                    } label: {
                        Label(tr("Standard view", "Vanlig visning"), systemImage: "rectangle.split.2x1")
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("athlth-gym-exit")
                    Button(action: onMinimize) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(tr("Minimize", "Minimer"))
                }
                .foregroundStyle(ATHLTHGymModeDisplay.gold)
                ATHLTHGymModeSplitView(guide: snapshot.gymExerciseGuide ?? legacyGymGuide, localBlock: nil) {
                    ATHLTHGymModeDisplay(snapshot: snapshot, local: false)
                }
                TrainTogetherStatusStrip()
                if snapshot.spotifyPlaying == true {
                    Label(snapshot.spotifyTrackTitle ?? tr("Music playing", "Musikk spiller"),
                          systemImage: "music.note")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Label(tr("Screen stays awake in Gym Mode", "Skjermen holdes våken i Gym Mode"),
                      systemImage: "sun.max")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            .padding(22)
            .frame(maxWidth: 1440)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            remoteControlPanel
                .environment(\.colorScheme, .light)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(ATHLTHGymModeDisplay.canvas)
        }
        .background(ATHLTHGymModeDisplay.canvas.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("athlth-ipad-gym-mode")
    }

    private var legacyGymGuide: ATHLTHGymExerciseReference? {
        // Older Watch snapshots may have only a title. Never guess a demo
        // from the name; show an honest unavailable state until ID arrives.
        guard isStrength, let title = snapshot.currentStep else { return nil }
        return ATHLTHGymExerciseReference(exerciseID: nil, slug: nil,
                                          title: title, upcoming: false)
    }

    private func sendRemoteAction(_ action: ATHLTHRemoteWorkoutAction) {
        Task {
            await liveSharing.enqueueRemoteControl(action, snapshot: snapshot,
                                                   accountID: session.profile.userID)
        }
    }

    private func controlLabel(_ action: ATHLTHRemoteWorkoutAction) -> (String, String) {
        switch action {
        case .pause: return (tr("Pause", "Pause"), "pause.fill")
        case .resume: return (tr("Resume", "Fortsett"), "play.fill")
        case .end: return (tr("End workout", "Avslutt økt"), "stop.fill")
        case .next: return (tr("Next step", "Neste deløkt"), "forward.end.fill")
        case .skipRest: return (tr("Skip rest", "Hopp over pause"), "forward.fill")
        }
    }

    private var remoteControlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tr("Workout controls", "Øktstyring"), systemImage: "ipad.and.iphone")
                    .font(.headline).foregroundStyle(ink)
                Spacer()
                if liveSharing.pendingRemoteControlID != nil { ProgressView().tint(bronze) }
            }
            if let actions = snapshot.supportedControls, !actions.isEmpty,
               snapshot.controlGrantID != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(actions, id: \.self) { action in remoteActionButton(action) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(actions, id: \.self) { action in remoteActionButton(action) }
                    }
                }
                .disabled(liveSharing.pendingRemoteControlID != nil ||
                          ATHLTHiPadLiveMetrics.isDelayed(snapshot, at: .now))
            } else {
                Text(tr("Ask your iPhone for permission to control this session.",
                        "Be iPhone om tillatelse til å styre denne økten."))
                    .font(.subheadline).foregroundStyle(secondary)
                Button {
                    Task { await liveSharing.requestAccess(accountID: session.profile.userID) }
                } label: {
                    Label(tr("Request control", "Be om styring"), systemImage: "lock.open")
                }
                .buttonStyle(.bordered)
                .tint(bronze)
                .disabled(liveSharing.outgoingRequestState == .sending ||
                          liveSharing.outgoingRequestState == .pending)
                if liveSharing.outgoingRequestState == .pending {
                    Text(tr("Waiting for approval on iPhone.", "Venter på godkjenning på iPhone."))
                        .font(.caption).foregroundStyle(secondary)
                }
            }
            if let message = liveSharing.remoteControlMessage {
                Text(message).font(.caption).foregroundStyle(secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("athlth-ipad-live-remote-controls")
    }

    private func remoteActionButton(_ action: ATHLTHRemoteWorkoutAction) -> some View {
        let label = controlLabel(action)
        return Button {
            if action == .end { confirmingRemoteEnd = true }
            else { sendRemoteAction(action) }
        } label: {
            Label(label.0, systemImage: label.1)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: gymMode ? 56 : 38)
        }
        .buttonStyle(.borderedProminent)
        .tint(action == .end ? .red : bronze)
        .accessibilityIdentifier("athlth-ipad-control-\(action.rawValue)")
    }

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 12) {
            HStack(spacing: 9) {
                Circle()
                    .fill(snapshot.paused == true ? Color.orange : bronze)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                Text(snapshot.paused == true
                    ? tr("PAUSED", "PAUSE")
                    : tr("LIVE WORKOUT", "TRENING PÅGÅR"))
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(bronze)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 5)) { context in
                Label(
                    ATHLTHiPadLiveMetrics.isDelayed(snapshot, at: context.date)
                        ? tr("Waiting for updates", "Venter på oppdatering")
                        : tr("Synced", "Synkronisert"),
                    systemImage: ATHLTHiPadLiveMetrics.isDelayed(
                        snapshot, at: context.date
                    ) ? "arrow.clockwise" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(secondary)
                .lineLimit(1)
            }

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { gymMode = true }
            } label: {
                Group {
                    if compact { Image(systemName: "display").accessibilityLabel("Gym Mode") }
                    else { Label("Gym Mode", systemImage: "display") }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(bronze)
            .accessibilityIdentifier("athlth-gym-enter")

            Toggle(isOn: $keepAwake) {
                if compact {
                    Image(systemName: "sun.max").accessibilityLabel(tr("Keep screen awake", "Hold skjermen på"))
                } else {
                    Label(tr("Keep screen awake", "Hold skjermen på"), systemImage: "sun.max")
                        .font(.caption)
                }
            }
            .toggleStyle(.switch)
            .tint(bronze)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("athlth-ipad-live-keep-awake")

            Button(action: onMinimize) {
                Group {
                    if compact {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .accessibilityLabel(tr("Minimize", "Minimer"))
                    } else {
                        Label(tr("Minimize", "Minimer"), systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-ipad-live-minimize")
        }
        .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 17) {
            Image(systemName: snapshot.symbol)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(bronze)
                .frame(width: 66, height: 66)
                .background(pale, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title)
                    .font(.system(size: 31, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    ATHLTHSpectatorSportMetricPolicy.isManual(
                        snapshot.captureEvidence
                    )
                        ? tr("IPHONE TIMER · MANUAL DATA", "IPHONE-TIDTAKER · MANUELLE DATA")
                        : isWatch
                        ? tr("LIVE FROM APPLE WATCH", "LIVE FRA APPLE WATCH")
                        : tr("LIVE FROM IPHONE", "LIVE FRA IPHONE"),
                    systemImage: isWatch ? "applewatch" : "iphone"
                )
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(bronze)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var elapsedHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("WORKOUT TIME", "ØKTTID"))
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(ATHLTHiPadLiveMetrics.duration(
                    ATHLTHiPadLiveMetrics.elapsed(snapshot, at: context.date)
                ))
                .font(.system(size: 76, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.60)
                .lineLimit(1)
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .linear(duration: 0.15),
                           value: Int(context.date.timeIntervalSince1970))
            }

            HStack(spacing: 10) {
                Label(
                    snapshot.paused == true
                        ? tr("Workout paused", "Økten er satt på pause")
                        : tr("Recording on source device", "Registreres på kildeenheten"),
                    systemImage: snapshot.paused == true
                        ? "pause.circle" : "record.circle"
                )
                .font(.subheadline)
                .foregroundStyle(bronze)
            }
        }
        .padding(25)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white, pale.opacity(0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(bronze.opacity(0.13), lineWidth: 1)
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 175), spacing: 13)],
            spacing: 13
        ) {
            if isStrength {
                metric(
                    tr("Completed sets", "Utførte sett"),
                    value: ATHLTHiPadLiveMetrics.sets(snapshot),
                    symbol: "checkmark.circle",
                    detail: tr("Workout progress", "Fremdrift")
                )
            } else if hasDistanceMetric {
                metric(
                    tr("Distance", "Distanse"),
                    value: ATHLTHiPadLiveMetrics.distance(snapshot.distanceMeters),
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    detail: snapshot.distanceMeters == nil
                        ? tr("Not available", "Ikke tilgjengelig") : nil
                )
            }

            if isPaceSport {
                metric(
                    tr("Current pace", "Nåværende tempo"),
                    value: ATHLTHiPadLiveMetrics.pace(
                        snapshot.currentPaceSecondsPerKilometer
                    ),
                    symbol: "speedometer",
                    detail: snapshot.paceIsTreadmillTarget == true
                        ? tr("Belt speed", "Møllehastighet") :
                        tr("min/km", "min/km")
                )
            }

            metric(
                tr("Heart rate", "Puls"),
                value: ATHLTHiPadLiveMetrics.heartRate(snapshot.heartRateBPM),
                symbol: "heart",
                detail: snapshot.heartRateBPM == nil
                    ? tr("Awaiting sensor data", "Ingen pulsdata fra kilden")
                    : tr("bpm", "slag/min")
            )

            if isCardio {
                if let zone = measuredZone {
                    metric(
                        tr("Heart rate zone now", "Pulssone nå"),
                        value: tr("Zone", "Sone") + " \(zone)",
                        symbol: "heart.text.square",
                        detail: tr("From measured pulse", "Fra målt puls")
                    )
                } else if let target = snapshot.targetHeartRateZone,
                          (1...5).contains(target) {
                    metric(
                        tr("Target heart rate zone", "Målpulssone"),
                        value: tr("Zone", "Sone") + " \(target)",
                        symbol: "heart.text.square",
                        detail: tr("Planned, not measured", "Planlagt, ikke målt")
                    )
                } else {
                    metric(
                        tr("Heart rate zone", "Pulssone"),
                        value: "—",
                        symbol: "heart.text.square",
                        detail: tr("Awaiting pulse and HRmax",
                                   "Venter på puls og makspuls")
                    )
                }
                if isPaceSport {
                    metric(
                        tr("Average pace", "Snittempo"),
                        value: ATHLTHiPadLiveMetrics.averagePace(snapshot),
                        symbol: "chart.line.uptrend.xyaxis",
                        detail: tr("Measured distance and active time",
                                   "Målt distanse og aktiv tid")
                    )
                } else if ATHLTHWorkoutSportMode(category: snapshot.kind) == .cycling {
                    metric(
                        tr("Average speed", "Snittfart"),
                        value: ATHLTHiPadLiveMetrics.averageSpeed(snapshot),
                        symbol: "speedometer",
                        detail: "km/t"
                    )
                } else if ATHLTHWorkoutSportMode(category: snapshot.kind) == .rowing {
                    metric(
                        tr("Average split", "Snittid per 500 m"),
                        value: ATHLTHiPadLiveMetrics.averageRowingSplit(snapshot),
                        symbol: "timer",
                        detail: "min/500 m"
                    )
                }
            } else {
                metric(
                    tr("Active calories", "Aktive kalorier"),
                    value: ATHLTHiPadLiveMetrics.calories(snapshot.activeCalories),
                    symbol: "flame",
                    detail: snapshot.activeCalories == nil
                        ? tr("No source data", "Ingen måling fra kilden") : "kcal"
                )
            }
        }
    }

    private func metric(
        _ label: String,
        value: String,
        symbol: String,
        detail: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(bronze)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(value)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 153, alignment: .topLeading)
        .background(surface, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(bronze.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var activeStepCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(
                    isStrength ? tr("CURRENT EXERCISE", "AKTIV ØVELSE")
                               : tr("CURRENT PHASE", "AKTIV DELØKT"),
                    systemImage: isStrength ? "dumbbell" : "square.stack.3d.up"
                )
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(bronze)

                Spacer()

                if let ordinal = snapshot.runningIntervalOrdinal,
                   let count = snapshot.runningIntervalTotal,
                   count > 1 {
                    Text(tr("Interval", "Drag") + " \(ordinal) / \(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(bronze)
                        .monospacedDigit()
                }
            }

            Text(snapshot.currentStep ??
                (isStrength
                    ? tr("Preparing next exercise", "Forbereder neste øvelse")
                    : tr("Free workout", "Fri trening")))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

            if let seconds = snapshot.runningStepRemainingSeconds,
               seconds.isFinite, seconds >= 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = ATHLTHiPadLiveMetrics.remaining(
                        snapshot, at: context.date
                    ) ?? seconds

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.runningInRecovery == true
                            ? tr("NEXT EFFORT IN", "NESTE DRAG OM")
                            : tr("TIME REMAINING", "GJENSTÅENDE TID"))
                            .font(.caption.weight(.medium))
                            .tracking(1)
                            .foregroundStyle(secondary)
                        Text(ATHLTHiPadLiveMetrics.duration(remaining))
                            .font(.system(size: 49, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                }
            }

            if snapshot.runningStepRemainingSeconds == nil,
               let remaining = snapshot.runningStepRemainingMeters,
               remaining.isFinite, remaining >= 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("DISTANCE REMAINING", "GJENSTÅENDE DISTANSE"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondary)
                    Text(String(format: "%.0f m", remaining))
                        .font(.system(size: 43, weight: .bold,
                                      design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                }
            }

            if let progress = ATHLTHiPadLiveMetrics.normalized(
                snapshot.runningStepProgress
            ) {
                ProgressView(value: progress)
                    .tint(bronze)
                    .accessibilityLabel(tr("Phase progress", "Deløktens fremdrift"))
            }

            if let next = snapshot.nextStep, !next.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(bronze)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("UP NEXT", "NESTE"))
                            .font(.caption2.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(secondary)
                        Text(next)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pale.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 25))
    }

    @ViewBuilder
    private var strengthProgress: some View {
        if let total = snapshot.totalSets, total > 0 {
            VStack(alignment: .leading, spacing: 13) {
                Text(tr("STRENGTH PROGRESS", "STYRKEFREMDRIFT"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)
                HStack {
                    Text(ATHLTHiPadLiveMetrics.sets(snapshot))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(tr("sets completed", "sett fullført"))
                        .font(.subheadline)
                        .foregroundStyle(secondary)
                }
                ProgressView(
                    value: min(1, Double(max(0, snapshot.completedSets ?? 0)) /
                        Double(total))
                )
                .tint(bronze)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        }
    }

    @ViewBuilder
    private var workoutProgress: some View {
        if let progress = ATHLTHiPadLiveMetrics.normalized(
            snapshot.runningOverallProgress
        ) {
            VStack(alignment: .leading, spacing: 13) {
                Text(tr("WORKOUT PROGRESS", "ØKTENS FREMDRIFT"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)
                HStack {
                    Text("\(Int((progress * 100).rounded())) %")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(tr("planned structure", "planlagt struktur"))
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
                ProgressView(value: progress)
                    .tint(bronze)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        } else if let interval = snapshot.runningIntervalOrdinal,
                  let total = snapshot.runningIntervalTotal, total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("INTERVALS", "INTERVALLER"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)
                Text("\(interval) / \(total)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                ProgressView(value: min(1, max(0, Double(interval) / Double(total))))
                    .tint(bronze)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        }
    }

    @ViewBuilder
    private var additionalDetails: some View {
        let hasTargets = snapshot.targetPaceSecondsPerKilometer != nil ||
            snapshot.targetHeartRateZone != nil
        if hasTargets {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("WORKOUT DETAILS", "ØKTDETALJER"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)

                if let pace = snapshot.targetPaceSecondsPerKilometer,
                   pace.isFinite, pace > 0 {
                    detailLine(
                        tr("Target pace", "Måltempo"),
                        value: ATHLTHiPadLiveMetrics.pace(pace),
                        symbol: "scope"
                    )
                }
                if let zone = snapshot.targetHeartRateZone, (1...5).contains(zone) {
                    detailLine(
                        tr("Target zone", "Målsone"),
                        value: tr("Zone", "Sone") + " \(zone)",
                        symbol: "heart.text.square"
                    )
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 23))
        }
    }

    private func detailLine(
        _ label: String, value: String, symbol: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(bronze)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Pure presentation calculations can be tested without creating HealthKit
/// or remote workout sessions and never invent absent sensor measurements.
enum ATHLTHiPadLiveMetrics {
    static func elapsed(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, at now: Date
    ) -> TimeInterval {
        let extra = snapshot.paused == true ? 0 :
            min(8, max(0, now.timeIntervalSince(snapshot.capturedAt ?? now)))
        return max(0, snapshot.elapsedSeconds + extra)
    }

    static func remaining(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, at now: Date
    ) -> TimeInterval? {
        guard let remaining = snapshot.runningStepRemainingSeconds,
              remaining.isFinite, remaining >= 0 else { return nil }
        let extra = snapshot.paused == true ? 0 :
            min(8, max(0, now.timeIntervalSince(snapshot.capturedAt ?? now)))
        return max(0, remaining - extra)
    }

    static func isDelayed(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, at now: Date
    ) -> Bool {
        guard let captured = snapshot.capturedAt else { return true }
        return now.timeIntervalSince(captured) > 14
    }

    static func normalized(_ progress: Double?) -> Double? {
        guard let progress, progress.isFinite, (0...1).contains(progress)
        else { return nil }
        return progress
    }

    static func duration(_ seconds: TimeInterval) -> String {
        // The UI may receive a malformed/legacy metric before a new poll.
        // Never convert NaN, infinity, or an unbounded Double to Int:
        // Swift traps on such conversions and would crash the entire iPad.
        guard seconds.isFinite, seconds <= 366 * 86_400 else { return "—" }
        let total = max(0, Int(seconds.rounded(.down)))
        let sec = total % 60
        let min = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, min, sec) }
        return String(format: "%02d:%02d", total / 60, sec)
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "—" }
        return String(format: "%.2f km", meters / 1_000)
    }

    static func pace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite,
              (120...1800).contains(secondsPerKm)
        else { return "—" }
        let value = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func averagePace(_ snapshot: ATHLTHCrossDeviceWorkoutSnapshot) -> String {
        guard let meters = snapshot.distanceMeters,
              meters.isFinite, meters >= 40,
              snapshot.elapsedSeconds >= 20 else { return "—" }
        return pace(snapshot.elapsedSeconds / (meters / 1_000))
    }

    /// Derived only from actual source distance and active time; a manual
    /// timer never receives invented HealthKit speed or rowing split.
    static func averageSpeed(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    ) -> String {
        guard ATHLTHWorkoutSportMode(category: snapshot.kind) == .cycling,
              !ATHLTHSpectatorSportMetricPolicy.isManual(snapshot.captureEvidence),
              let meters = snapshot.distanceMeters, meters.isFinite,
              meters >= 250, snapshot.elapsedSeconds.isFinite,
              snapshot.elapsedSeconds > 0 else { return "—" }
        let speed = meters * 3.6 / snapshot.elapsedSeconds
        guard speed.isFinite, (1...100).contains(speed) else { return "—" }
        return String(format: "%.1f", speed)
    }

    static func averageRowingSplit(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    ) -> String {
        guard ATHLTHWorkoutSportMode(category: snapshot.kind) == .rowing,
              !ATHLTHSpectatorSportMetricPolicy.isManual(snapshot.captureEvidence),
              let meters = snapshot.distanceMeters, meters.isFinite,
              meters >= 250, snapshot.elapsedSeconds.isFinite,
              snapshot.elapsedSeconds > 0 else { return "—" }
        let split = snapshot.elapsedSeconds * 500 / meters
        guard split.isFinite, (40...1800).contains(split) else { return "—" }
        let rounded = Int(split.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm.isFinite, (35...240).contains(bpm) else { return "—" }
        return String(Int(bpm.rounded()))
    }

    static func calories(_ calories: Double?) -> String {
        guard let calories, calories.isFinite, (0...1_000_000).contains(calories),
              calories > 0 else { return "—" }
        return "\(Int(calories.rounded()))"
    }

    static func sets(_ snapshot: ATHLTHCrossDeviceWorkoutSnapshot) -> String {
        guard let done = snapshot.completedSets else { return "—" }
        if let total = snapshot.totalSets, total > 0 {
            return "\(min(max(0, done), total)) / \(total)"
        }
        return "\(max(0, done))"
    }
}


/// Large, high-contrast readout. Neither this view nor its clock starts a
/// workout or advances a stage. The original engine remains authoritative.
enum ATHLTHGymModeClock {
    static func restRemaining(_ snapshot: ATHLTHCrossDeviceWorkoutSnapshot,
                              at now: Date) -> TimeInterval? {
        guard let deadline = snapshot.strengthRestEndsAt,
              let captured = snapshot.capturedAt,
              deadline.timeIntervalSince1970.isFinite,
              captured.timeIntervalSince1970.isFinite else { return nil }
        let initial = deadline.timeIntervalSince(captured)
        guard initial > 0, initial <= 86_400 else { return nil }
        let extra = snapshot.paused == true ? 0 : min(8, max(0, now.timeIntervalSince(captured)))
        return max(0, initial - extra)
    }

    static func fraction(remaining: TimeInterval?, duration: TimeInterval?) -> Double? {
        guard let remaining, let duration, remaining.isFinite, duration.isFinite,
              duration > 0, remaining >= 0 else { return nil }
        return min(1, remaining / duration)
    }

    static func countdown(_ snapshot: ATHLTHCrossDeviceWorkoutSnapshot,
                          at now: Date) -> TimeInterval? {
        restRemaining(snapshot, at: now) ?? ATHLTHiPadLiveMetrics.remaining(snapshot, at: now)
    }
}

struct ATHLTHGymModeDisplay: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let local: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let canvas = Color(red: 0.07, green: 0.075, blue: 0.085)
    static let gold = Color(red: 0.84, green: 0.72, blue: 0.49)
    private let panel = Color(red: 0.13, green: 0.14, blue: 0.16)

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.title)
                        .font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.68))
                    Text(snapshot.currentStep ?? tr("Free workout", "Fri trening"))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: snapshot.currentStep)
                }
                Spacer(minLength: 0)
                Image(systemName: snapshot.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Self.gold)
                    .accessibilityHidden(true)
            }
            if let next = snapshot.nextStep, !next.isEmpty {
                Label(tr("Up next", "Neste") + " · " + next, systemImage: "arrow.turn.down.right")
                    .font(.title3.weight(.medium)).foregroundStyle(Self.gold)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let remaining = ATHLTHGymModeClock.countdown(snapshot, at: now)
                let rest = ATHLTHGymModeClock.restRemaining(snapshot, at: now) != nil ||
                    snapshot.runningInRecovery == true
                let delayed = !local && ATHLTHiPadLiveMetrics.isDelayed(snapshot, at: now)
                VStack(spacing: 8) {
                    Text(snapshot.paused == true ? tr("PAUSED", "PAUSET") :
                         delayed ? tr("WAITING FOR SOURCE", "VENTER PÅ OPPDATERING") :
                         rest ? tr("RECOVERY", "PAUSE") :
                         remaining != nil ? tr("TIME LEFT", "TID IGJEN") :
                         tr("WORKOUT TIME", "ØKTTID"))
                        .font(.headline.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(delayed ? .orange : Self.gold)
                    ZStack {
                        if let fraction = ATHLTHGymModeClock.fraction(
                            remaining: remaining, duration: snapshot.gymStageDuration ??
                                (ATHLTHGymModeClock.restRemaining(snapshot, at: now) == nil
                                    ? snapshot.runningSteps?.first(where: { $0.index == snapshot.runningStepIndex })?.durationSeconds
                                    : nil)
                        ) {
                            Circle().stroke(Self.gold.opacity(0.12), lineWidth: 8)
                            Circle().trim(from: 0, to: fraction)
                                .stroke(AngularGradient(colors: [Self.gold.opacity(0.48), Self.gold, .white],
                                                        center: .center),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion || delayed || snapshot.paused == true ? nil :
                                    .linear(duration: 0.45), value: fraction)
                        }
                        Text(ATHLTHiPadLiveMetrics.duration(remaining ??
                             ATHLTHiPadLiveMetrics.elapsed(snapshot, at: now)))
                            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 55 : 100,
                                          weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.35)
                            .padding(24)
                            .contentTransition(.numericText(countsDown: remaining != nil))
                            .animation(reduceMotion || delayed ? nil : .easeOut(duration: 0.18),
                                       value: ATHLTHiPadLiveMetrics.duration(remaining ??
                                           ATHLTHiPadLiveMetrics.elapsed(snapshot, at: now)))
                            .accessibilityLabel((remaining == nil ? tr("Workout time", "Økttid") :
                                tr("Time remaining", "Tid igjen")) + " " +
                                ATHLTHiPadLiveMetrics.duration(remaining ??
                                    ATHLTHiPadLiveMetrics.elapsed(snapshot, at: now)))
                    }
                    .frame(maxWidth: 270)
                    .frame(height: 220)
                    if remaining != nil {
                        Text(tr("Total", "Totalt") + " · " +
                             ATHLTHiPadLiveMetrics.duration(ATHLTHiPadLiveMetrics.elapsed(snapshot, at: now)))
                            .font(.title2.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                    }
                    if delayed {
                        Text(tr("Last known values. Controls are disabled until sync resumes.",
                                "Sist kjente verdier. Styring krever oppdatert synkronisering."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(panel, in: RoundedRectangle(cornerRadius: 26))
                .accessibilityIdentifier("athlth-gym-clock")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 150), spacing: 12)], spacing: 12) {
                if let step = snapshot.runningIntervalOrdinal, let count = snapshot.runningIntervalTotal, count > 0 {
                    metric(tr("Interval", "Drag"), "\(step) / \(count)")
                } else if let step = snapshot.runningStepIndex, let count = snapshot.runningStepCount, count > 0 {
                    metric(tr("Step", "Deløkt"), "\(min(step + 1, count)) / \(count)")
                }
                if let set = snapshot.strengthSetNumber, let total = snapshot.strengthSetTotal, total > 0 {
                    metric(tr("Set", "Sett"), "\(set) / \(total)")
                } else if snapshot.completedSets != nil && snapshot.captureEvidence != "structuredManual" {
                    metric(tr("Completed sets", "Fullførte sett"), ATHLTHiPadLiveMetrics.sets(snapshot))
                }
                if let reps = snapshot.strengthReps, reps >= 0 { metric(tr("Target reps", "Målreps"), "\(reps)") }
                if let kg = snapshot.strengthWeightKilograms, kg.isFinite, kg >= 0 {
                    metric(tr("Target load", "Målvekt"), "\(kg.formatted()) kg")
                }
                if !ATHLTHSpectatorSportMetricPolicy.isManual(snapshot.captureEvidence) {
                    metric(tr("Heart rate · bpm", "Puls · slag/min"), ATHLTHiPadLiveMetrics.heartRate(snapshot.heartRateBPM))
                    if ATHLTHSpectatorSportMetricPolicy.supportsDistance(snapshot.kind) {
                        metric(tr("Distance", "Distanse"), ATHLTHiPadLiveMetrics.distance(snapshot.distanceMeters))
                    }
                    if ATHLTHSpectatorSportMetricPolicy.supportsRunningPace(snapshot.kind) {
                        metric(snapshot.paceIsTreadmillTarget == true ? tr("Belt pace · min/km", "Mølletempo · min/km") :
                            tr("Pace · min/km", "Tempo · min/km"), ATHLTHiPadLiveMetrics.pace(snapshot.currentPaceSecondsPerKilometer))
                    }
                }
            }
            if let progress = ATHLTHiPadLiveMetrics.normalized(snapshot.runningOverallProgress) ??
                (snapshot.totalSets.flatMap { total in
                    total > 0 ? min(1, max(0, Double(snapshot.completedSets ?? 0) / Double(total))) : nil
                }) {
                ProgressView(value: progress)
                    .tint(Self.gold)
                    .accessibilityLabel(tr("Workout progress", "Øktfremdrift"))
            }
        }
        .padding(20)
        .background(Self.canvas, in: RoundedRectangle(cornerRadius: 24))
        .environment(\.colorScheme, .dark)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.65))
            Text(value).font(.system(size: 39, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.45).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}


/// A width-aware two-column layout without a GeometryReader inside ScrollView.
/// In a compact Stage Manager window, preserve all content in reading order.
private struct ATHLTHGymSplitLayout: Layout {
    let compact: Bool
    let gap: CGFloat = 18

    private func widths(_ proposed: CGFloat) -> (CGFloat, CGFloat) {
        let left = max(0, (proposed - gap) * 0.42)
        return (left, max(0, proposed - gap - left))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 1000
        if compact || width < 760 {
            let sizes = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)) }
            return CGSize(width: width, height: sizes[0].height + gap + sizes[1].height)
        }
        let (left, right) = widths(width)
        let a = subviews[0].sizeThatFits(.init(width: left, height: nil))
        let b = subviews[1].sizeThatFits(.init(width: right, height: nil))
        return CGSize(width: width, height: max(a.height, b.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if compact || bounds.width < 760 {
            let height = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil)).height
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + height + gap),
                              anchor: .topLeading, proposal: .init(width: bounds.width, height: nil))
        } else {
            let (left, right) = widths(bounds.width)
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: left, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + left + gap, y: bounds.minY),
                              anchor: .topLeading, proposal: .init(width: right, height: nil))
        }
    }
}

struct ATHLTHGymModeSplitView<WorkoutContent: View>: View {
    let guide: ATHLTHGymExerciseReference?
    let localBlock: WorkoutTemplateBlock?
    @ViewBuilder let workoutContent: () -> WorkoutContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if ATHLTHDeviceRole.isIPad, let guide {
            ATHLTHGymSplitLayout(compact: dynamicTypeSize.isAccessibilitySize) {
                ATHLTHGymExercisePanel(reference: guide, localBlock: localBlock)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                workoutContent().frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: guide)
            .accessibilityIdentifier("athlth-gym-split")
        } else {
            workoutContent()
        }
    }
}

private struct ATHLTHGymExercisePanel: View {
    let reference: ATHLTHGymExerciseReference
    let localBlock: WorkoutTemplateBlock?
    @EnvironmentObject private var library: ExerciseLibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = ATHLTHGymModeDisplay.gold

    private var entry: ExerciseLibraryEntry? {
        if let localBlock,
           let resolved = ATHLTHExerciseReferenceResolver.resolve(localBlock, in: library.allExercises) {
            return resolved
        }
        if let id = reference.exerciseID {
            return library.allExercises.first { $0.id == id }
        }
        if let slug = reference.slug {
            let matches = library.allExercises.filter { $0.sourceIdentifier == slug }
            return matches.count == 1 ? matches.first : nil
        }
        return nil
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        let matched = entry
        let fallback = localBlock?.exerciseSnapshot
        let instructions = matched.map { library.localizedExerciseInstructions($0) } ?? fallback?.instructions ?? []
        let muscles = matched?.exercise.primaryMuscles ?? fallback?.primaryMuscles ?? []
        let secondary = matched?.exercise.secondaryMuscles ?? fallback?.secondaryMuscles ?? []
        let equipment = matched?.exercise.equipment ?? fallback?.equipment ?? []
        let video = matched?.exercise.videoURL ?? fallback?.videoURL
        let start = matched?.imageStartURL ?? matched?.exercise.imageURL ?? fallback?.imageURL
        let peak = matched?.imagePeakURL
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(reference.upcoming ? tr("NEXT EXERCISE", "NESTE ØVELSE") : tr("TECHNIQUE", "TEKNIKK"))
                    .font(.caption.weight(.bold)).tracking(2).foregroundStyle(gold)
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(gold)
            }
            Text(matched.map { library.localizedExerciseName($0) } ?? reference.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            ATHLTHGymExerciseMedia(video: video, start: start, peak: peak)
                .id([video?.absoluteString, start?.absoluteString, peak?.absoluteString].compactMap { $0 }.joined(separator: "|"))
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(gold.opacity(0.18)) }
            if !muscles.isEmpty {
                metadata(tr("Primary muscles", "Hovedmuskler"), muscles.joined(separator: " · "))
            }
            if !secondary.isEmpty {
                metadata(tr("Secondary muscles", "Sekundærmuskler"), secondary.joined(separator: " · "))
            }
            if !equipment.isEmpty {
                metadata(tr("Equipment", "Utstyr"), equipment.joined(separator: " · "))
            }
            if !instructions.isEmpty {
                Text(tr("How to perform", "Slik gjør du øvelsen"))
                    .font(.headline).foregroundStyle(gold)
                ForEach(Array(instructions.prefix(4).enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold)).foregroundStyle(gold)
                            .frame(width: 26, height: 26)
                            .background(gold.opacity(0.12), in: Circle())
                        Text(instruction).font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(tr("No verified exercise instructions available on this iPad.",
                        "Ingen bekreftet øvelsesguide tilgjengelig på denne iPaden."))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.15, blue: 0.14),
                                            Color(red: 0.10, green: 0.11, blue: 0.13)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(gold.opacity(0.16)) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: reference)
        .accessibilityIdentifier("athlth-gym-exercise-panel")
    }

    private func metadata(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(gold)
            Text(value).font(.subheadline).foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct ATHLTHGymExerciseMedia: View {
    let video: URL?
    let start: URL?
    let peak: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPeak = false
    @State private var videoFailed = false

    private func allowed(_ url: URL?) -> URL? {
        guard let url else { return nil }
        return url.isFileURL || url.scheme?.lowercased() == "https" ? url : nil
    }

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.11)
            if let video = allowed(video), !videoFailed {
                ATHLTHGymLoopVideo(url: video, autoplay: !reduceMotion && scenePhase == .active,
                                   failed: { videoFailed = true })
            } else if let url = allowed(showPeak ? (peak ?? start) : (start ?? peak)) {
                Group {
                    if url.isFileURL {
                        ATHLTHLocalExerciseThumbnailView(url: url, size: 280,
                                                        fallbackSymbol: "figure.strengthtraining.traditional")
                    } else {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else { placeholder }
                        }
                    }
                }
                .id(url)
                .transition(.opacity)
            } else { placeholder }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(scenePhase)-\(reduceMotion)-\(videoFailed)") {
            guard !reduceMotion, scenePhase == .active,
                  (allowed(video) == nil || videoFailed),
                  allowed(start) != nil, allowed(peak) != nil, start != peak else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.35)) { showPeak.toggle() }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56, weight: .light)).foregroundStyle(ATHLTHGymModeDisplay.gold)
            Text(ATHLTHLocalization.choose(english: "No demonstration available", norwegian: "Ingen demonstrasjon tilgjengelig"))
                .font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .padding()
    }
}

private struct ATHLTHGymLoopVideo: View {
    let url: URL
    let autoplay: Bool
    let failed: () -> Void
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                player.pause()
                looper = nil
                player.removeAllItems()
                player.isMuted = true
                let item = AVPlayerItem(url: url)
                looper = AVPlayerLooper(player: player, templateItem: item)
                if autoplay { player.play() }
                // VideoPlayer may fail for a file absent on this iPad.
                // Fall back to verified library images, not a guessed video.
                while !Task.isCancelled {
                    if player.currentItem?.status == .failed || looper?.status == .failed {
                        failed()
                        return
                    }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .onChange(of: autoplay) { _, active in
                if active { player.play() } else { player.pause() }
            }
            .onDisappear {
                player.pause()
                looper = nil
                player.removeAllItems()
            }
    }
}
