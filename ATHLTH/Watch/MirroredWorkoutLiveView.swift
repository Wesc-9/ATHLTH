import SwiftUI
import AVFoundation

struct MirroredWorkoutLiveView: View {
    @EnvironmentObject private var mirroring: WorkoutMirroringStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingTreadmillInclineEditor = false
    @State private var treadmillInclineDraft = 0.0
    @State private var coachOutputName: String?
    @State private var showingAIConversation = false
    @State private var showingAddRunningWorkout = false
    @State private var showingSpotifyControls = false
    @State private var showingTargetPaceEditor = false
    @State private var targetPaceDraftSeconds = 330.0
    @State private var enteredTargetPaceSeconds: Double?
    @State private var paceSamples: [(elapsed: Double, distance: Double)] = []
    @State private var rollingPaceSeconds: TimeInterval?
    @State private var paceWorkoutStart: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    TrainTogetherStatusStrip()

                    if let snapshot = mirroring.snapshot {
                        if ghostRace.reference != nil &&
                            snapshot.kind == .running {
                            GhostRaceLivePanel(
                                snapshot: snapshot
                            )
                            .environmentObject(
                                ghostRace
                            )

                            Button {
                                ghostRace.cancel()
                                watchConnection.clearGhostRace()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Turn off Ghost Race",
                                        norwegian: "Slå av Ghost Race"
                                    ),
                                    systemImage: "eye.slash"
                                )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint(ATHLTHLocalization.choose(
                                english: "Stop Ghost comparisons but keep recording the run",
                                norwegian: "Stopp Ghost-sammenligningen uten å avslutte løpeøkten"
                            ))
                        } else if snapshot.kind ==
                                    .running,
                                  realtime
                                    .selectedLiveGhostSessionID !=
                                    nil {
                            liveGhostRaceCard(
                                snapshot
                            )
                        }

                        if snapshot.kind == .running ||
                           snapshot.kind == .walking {
                            runningDashboard(snapshot)
                            if snapshot.routeTitle != nil {
                                mirroredRouteNextTurnCard(snapshot)
                                if snapshot.routeCanReturnToStart == true {
                                    Button {
                                        _ = mirroring.requestRunBackToStart()
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Run back to start",
                                                norwegian: "Løp tilbake til start"
                                            ),
                                            systemImage: "arrow.uturn.backward"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(
                                            ATHLTHPlanDesign.accentInk,
                                            in: RoundedRectangle(cornerRadius: 15)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(ATHLTHLocalization.choose(
                                        english: "Keep recording and reverse navigation to the starting point",
                                        norwegian: "Fortsett å registrere økten og følg ruten tilbake"
                                    ))
                                }
                            }
                        } else {
                            if snapshot.kind == .strength {
                                mirroredStrengthSummary(snapshot)
                            } else {
                                mirroredOtherSportHeader(snapshot)
                            }

                            if snapshot.kind == .strength {
                                timer(snapshot)
                            } else if snapshot.kind == .cycling,
                                      ATHLTHOtherSportLiveResolver.resolve(
                                          kind: .cycling,
                                          distanceMeters: snapshot.distanceMeters
                                      ) == .measuredDistance {
                                mirroredCyclingDistance(snapshot)
                            }

                            HStack(
                                spacing: 12
                            ) {
                                metricCard(
                                    title:
                                        ATHLTHLocalization.choose(english: "Heart rate", norwegian: "Puls"),
                                    value:
                                        ATHLTHCoachSensorFreshness.validHeartRate(
                                            snapshot.heartRate,
                                            sampledAt: snapshot.coachHeartRateSampleAt
                                        )
                                            ? "\(Int(snapshot.heartRate.rounded()))"
                                            : "—",
                                    unit: "bpm",
                                    icon:
                                        "heart.fill"
                                )

                                metricCard(
                                    title:
                                        ATHLTHLocalization.choose(english: "Calories", norwegian: "Kalorier"),
                                    value:
                                        "\(Int(snapshot.activeCalories.rounded()))",
                                    unit: "kcal",
                                    icon:
                                        "flame.fill"
                                )

                                if snapshot.kind
                                    .supportsDistanceMetric &&
                                    snapshot.kind != .cycling {
                                    metricCard(
                                        title:
                                            "Distance",
                                        value:
                                            String(
                                                format:
                                                    "%.2f",
                                                snapshot
                                                    .distanceMeters /
                                                1000
                                            ),
                                        unit: "km",
                                        icon:
                                            "location.fill"
                                    )
                                }
                            }
                        }

                        if mirroring.mirroredIPhoneCoachAvailable {
                            mirroredAudioCoachCard
                        }

                        if mirroring.hasActiveMirroredWorkout {
                            Button {
                                showingAIConversation = true
                            } label: {
                                ATHLTHUnifiedCard {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mic.circle.fill")
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                            .font(.title2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ATHLTHLocalization.choose(
                                                english: "Talk to AI Coach",
                                                norwegian: "Snakk med AI Coach"
                                            ))
                                            .font(.subheadline.weight(.semibold))
                                            Text(ATHLTHLocalization.choose(
                                                english: "Optional · confirm microphone on iPhone",
                                                norwegian: "Valgfritt · godkjenn mikrofon på iPhone"
                                            ))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if let liveSession =
                            realtime.currentSession,
                           realtime.isSharingLiveLocation {
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: liveSession
                                )
                            } label: {
                                ATHLTHUnifiedCard {
                                    HStack {
                                        Label(
                                            liveSession.ghostChallengeID ==
                                                nil
                                                ? "Live position"
                                                : "Live Ghost Run",
                                            systemImage:
                                                "location.circle.fill"
                                        )
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )

                                        Spacer()

                                        Image(
                                            systemName:
                                                "chevron.right"
                                        )
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if snapshot.kind !=
                            .running {
                            ATHLTHUnifiedCard {
                                HStack {
                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 5
                                    ) {
                                        Text(
                                            "Apple Watch"
                                        )
                                        .font(
                                            .headline
                                        )

                                        Text(
                                            mirroring
                                                .connectionText
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }

                                    Spacer()

                                    Label(
                                        statusTitle(
                                            snapshot
                                                .state
                                        ),
                                        systemImage:
                                            statusIcon(
                                                snapshot
                                                    .state
                                            )
                                    )
                                    .font(
                                        .caption
                                            .weight(
                                                .semibold
                                            )
                                    )
                                    .foregroundStyle(
                                        statusColor(
                                            snapshot
                                                .state
                                        )
                                    )
                                }
                            }
                        }

                        if let errorMessage = mirroring.errorMessage {
                            Label(
                                errorMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Workout actions live in the fixed safe-area dock
                        // below the scrollable health and Coach content.
                    } else {
                        ContentUnavailableView(
                            "Waiting for Apple Watch",
                            systemImage: "applewatch",
                            description: Text(
                                "Start an ATHLTH workout on Apple Watch to mirror it here."
                            )
                        )
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Live Workout",
                    norwegian: "Live økt"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let snapshot = mirroring.snapshot {
                    controls(snapshot)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showingSpotifyControls && spotify.isConnected {
                    HStack {
                        Spacer(minLength: 0)
                        mirroredSpotifyBar
                            .padding(.trailing, 13)
                    }
                    .padding(.vertical, 4)
                    .background(.regularMaterial)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar {
                if mirroring
                    .hasActiveMirroredWorkout {
                    ToolbarItem(
                        placement:
                            .topBarLeading
                    ) {
                        Button {
                            mirroring
                                .minimizeWorkout()
                        } label: {
                            Image(
                                systemName:
                                    "chevron.down"
                            )
                            .font(
                                .system(
                                    size: 16,
                                    weight:
                                        .semibold
                                )
                            )
                        }
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Minimize workout",
                                norwegian:
                                    "Legg ned økten"
                            )
                        )
                    }
                }

                if spotify.isConnected && mirroring.hasActiveMirroredWorkout {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showingSpotifyControls.toggle()
                            }
                        } label: {
                            ATHLTHSpotifyGlyph()
                                .frame(width: 24, height: 24)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Show or hide Spotify controls",
                            norwegian: "Vis eller skjul Spotify-kontroller"
                        ))
                    }
                }

                // Use the run's top-right + for real, supported in-session
                // actions. The Watch owns this recording; do not offer an
                // unimplemented second workout recorder from this screen.
                if let snapshot = mirroring.snapshot,
                   mirroring.hasActiveMirroredWorkout,
                   snapshot.kind == .running {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingAddRunningWorkout = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Add interval workout",
                                        norwegian: "Legg til intervalløkt"
                                    ),
                                    systemImage: "rectangle.stack.badge.plus"
                                )
                            }

                            if let incline = snapshot.treadmillInclinePercent {
                                Button {
                                    treadmillInclineDraft = incline
                                    showingTreadmillInclineEditor = true
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Adjust treadmill incline",
                                            norwegian: "Juster stigning på mølle"
                                        ),
                                        systemImage: "figure.run"
                                    )
                                }
                            }

                            if snapshot.routeCanReturnToStart == true {
                                Button {
                                    _ = mirroring.requestRunBackToStart()
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Run back to start",
                                            norwegian: "Løp tilbake til start"
                                        ),
                                        systemImage: "arrow.uturn.backward"
                                    )
                                }
                            }

                            Button {
                                showingAIConversation = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Talk to AI Coach",
                                        norwegian: "Snakk med AI Coach"
                                    ),
                                    systemImage: "waveform"
                                )
                            }

                            if mirroring.canReplayMirroredCoachMessage {
                                Button {
                                    mirroring.replayMirroredCoachMessage()
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Replay last coach message",
                                            norwegian: "Hør siste coachbeskjed"
                                        ),
                                        systemImage: "arrow.counterclockwise"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "More live workout actions",
                            norwegian: "Flere valg under økten"
                        ))
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRunningWorkout) {
            ActiveHybridWorkoutPicker(runningOnly: true) { session, startNow in
                guard let template = session.runningWorkout else {
                    return false
                }
                return mirroring.appendRunningWorkout(
                    template, startNow: startNow
                )
            }
            .environmentObject(runningLibrary)
        }
        .sheet(isPresented: $showingAIConversation) {
            ATHLTHGroqVoiceCoachView(source: .mirroredWatchWorkout)
                .environmentObject(settings)
                .environmentObject(mirroring)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented:
                $showingTreadmillInclineEditor
        ) {
            TreadmillInclineEditorView(
                initialValue:
                    treadmillInclineDraft
            ) { value in
                _ = mirroring
                    .sendTreadmillInclinePercent(
                        value
                    )
                treadmillInclineDraft =
                    value
            }
        }
        .sheet(isPresented: $showingTargetPaceEditor) {
            NavigationStack {
                Form {
                    Section {
                        Stepper(
                            String(format: "%.1f km/t · %d:%02d/km",
                                3_600 / targetPaceDraftSeconds,
                                Int(targetPaceDraftSeconds) / 60,
                                Int(targetPaceDraftSeconds) % 60),
                            value: $targetPaceDraftSeconds,
                            in: 120...1200, step: 5
                        )
                        Slider(value: $targetPaceDraftSeconds,
                               in: 120...1200, step: 5)
                    } footer: {
                        Text(ATHLTHLocalization.choose(
                            english: "A manually chosen target. Actual pace comes from Apple Watch and is not overwritten.",
                            norwegian: "Et manuelt mål. Faktisk tempo måles av Apple Watch og endres ikke."
                        ))
                    }
                }
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Target pace", norwegian: "Måltempo"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        )) { showingTargetPaceEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Save", norwegian: "Lagre"
                        )) {
                            if mirroring.sendTreadmillTargetPaceSecondsPerKilometer(
                                targetPaceDraftSeconds
                            ) {
                                enteredTargetPaceSeconds = targetPaceDraftSeconds
                                showingTargetPaceEditor = false
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: mirroring.snapshot?.capturedAt) { _, _ in
            guard let snap = mirroring.snapshot else { return }
            updateRollingPace(with: snap)
        }
        .interactiveDismissDisabled(mirroring.hasActiveMirroredWorkout)
        .task(
            id: mirroring.snapshot?
                .capturedAt
        ) {
            await syncLivePosition()
        }
        .onChange(of: mirroring.ghostDisableRequestGeneration) { _, _ in
            if ghostRace.reference != nil {
                ghostRace.cancel()
            }
        }
        .onAppear {
            mirroring.liveViewDidAppear()
            coachOutputName = AVAudioSession.sharedInstance()
                .currentRoute.outputs.first?.portName
            updateScreenAwakeState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVAudioSession.routeChangeNotification
            )
        ) { _ in
            coachOutputName = AVAudioSession.sharedInstance()
                .currentRoute.outputs.first?.portName
        }
        .onDisappear {
            mirroring.liveViewDidDisappear()
            ATHLTHWorkoutScreenAwake.set(
                false,
                reason: "watch-mirrored-workout"
            )
        }
        .onChange(of: watchConnection.latestAIConversationRequestID) { _, request in
            if request != nil &&
               mirroring.hasActiveMirroredWorkout &&
               scenePhase == .active {
                // A Watch request opens a choice, never microphone capture.
                showingAIConversation = true
            }
        }
        .onChange(
            of:
                mirroring
                    .hasActiveMirroredWorkout
        ) { _, isActive in
            if !isActive { showingAIConversation = false }
            updateScreenAwakeState()
        }
        .onChange(
            of: scenePhase
        ) { _, _ in
            updateScreenAwakeState()
        }
    }

    private var mirroredAudioCoachCard: some View {
        ATHLTHUnifiedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Audio Coach")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            mirroring.isIPhoneCoachVoiceOwner
                                ? ATHLTHLocalization.choose(
                                    english: "Voice on iPhone",
                                    norwegian: "Tale på iPhone"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Voice on Apple Watch",
                                    norwegian: "Tale på Apple Watch"
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 4)


                }

                if mirroring.isIPhoneCoachVoiceOwner {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2")
                        Text(coachOutputName ??
                            ATHLTHLocalization.choose(
                                english: "System audio output",
                                norwegian: "Systemets lydutgang"
                            )
                        )
                        .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Text(mirroring.lastCoachMessage ??
                    ATHLTHLocalization.choose(
                        english: "No iPhone coach message yet",
                        norwegian: "Ingen coachbeskjed på iPhone ennå"
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(2)

                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Button {
                        mirroring.replayMirroredCoachMessage()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Listen again on iPhone",
                                norwegian: "Hør igjen på iPhone"
                            ),
                            systemImage: "arrow.counterclockwise"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!mirroring.canReplayMirroredCoachMessage)
                }
            }
        }
    }

    private func updateScreenAwakeState() {
        ATHLTHWorkoutScreenAwake.set(
            mirroring
                .hasActiveMirroredWorkout &&
                scenePhase == .active,
            reason: "watch-mirrored-workout"
        )
    }

    private func mirroredRouteNextTurnCard(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> some View {
        let offRoute = snapshot.routeCueOffRoute == true
        let cue = ATHLTHLocalization.isNorwegian
            ? snapshot.routeCueNorwegian : snapshot.routeCueEnglish
        let message = cue ?? ATHLTHLocalization.choose(
            english: "Follow the highlighted route.",
            norwegian: "Følg den markerte ruten videre."
        )
        let distance = snapshot.routeCueDistanceMeters.flatMap { meters in
            meters.isFinite && meters >= 0 ? meters : nil
        }
        return ATHLTHUnifiedCard {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: snapshot.routeCueSymbol ?? "arrow.up")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        offRoute ? Color.orange : ATHLTHPlanDesign.accentInk
                    )
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: offRoute ? "BACK TO ROUTE" : "NEXT TURN",
                        norwegian: offRoute ? "TILBAKE TIL RUTEN" : "NESTE SVING"
                    ))
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 3)
                if let distance {
                    Text(distance < 1000
                        ? String(format: "%.0f m", distance)
                        : String(format: "%.1f km", distance / 1000))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(
                            offRoute ? Color.orange : ATHLTHPlanDesign.accentInk
                        )
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func liveGhostRaceCard(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> some View {
        if let session =
                realtime
                    .selectedLiveGhostSession {
            let comparison =
                realtime
                    .liveGhostComparison(
                        ownDistanceMeters:
                            snapshot
                                .distanceMeters,
                        ownElapsedSeconds:
                            snapshot
                                .elapsedTime,
                        ownRouteKey:
                            snapshot
                                .routeComparisonID,
                        ownRouteProgressPercent:
                            snapshot
                                .routeProgressPercent,
                        ownRouteDeviationMeters:
                            snapshot
                                .routeDeviationMeters
                    )

            ATHLTHUnifiedCard {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text("LIVE GHOST")
                                .font(
                                    .caption2
                                        .weight(.bold)
                                )
                                .tracking(1.5)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )

                            Text(
                                liveGhostOpponentName(
                                    session
                                )
                            )
                            .font(
                                .headline
                            )
                        }

                        Spacer()

                        Circle()
                            .fill(
                                Color.green
                            )
                            .frame(
                                width: 9,
                                height: 9
                            )

                        Text("LIVE")
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                Color.green
                            )
                    }

                    if let comparison {
                        HStack(
                            alignment: .firstTextBaseline
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    comparison
                                        .userIsAhead
                                        ? "YOU ARE AHEAD"
                                        : "GHOST IS AHEAD"
                                )
                                .font(
                                    .caption
                                        .weight(.semibold)
                                )
                                .foregroundStyle(
                                    comparison
                                        .userIsAhead
                                        ? ATHLTHTheme
                                            .vitality
                                        : Color.orange
                                )

                                Text(
                                    signedDistanceText(
                                        comparison
                                            .signedDistanceMeters
                                    )
                                )
                                .font(
                                    .system(
                                        size: 34,
                                        weight: .bold,
                                        design:
                                            .rounded
                                    )
                                )
                                .monospacedDigit()
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                            }

                            Spacer()

                            if let seconds =
                                comparison
                                    .estimatedTimeDeltaSeconds {
                                VStack(
                                    alignment: .trailing,
                                    spacing: 3
                                ) {
                                    Text("EST. GAP")
                                        .font(
                                            .caption2
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            .secondary
                                        )

                                    Text(
                                        signedTimeText(
                                            seconds
                                        )
                                    )
                                    .font(
                                        .title3
                                            .weight(.bold)
                                            .monospacedDigit()
                                    )

                                    Text("approx.")
                                        .font(.caption2)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Label(
                                comparison
                                    .isRouteAware
                                    ? "Route matched"
                                    : String(
                                        format:
                                            "%.2f km",
                                        comparison
                                            .opponentDistanceMeters /
                                            1_000
                                    ),
                                systemImage:
                                    comparison
                                        .isRouteAware
                                        ? "point.topleft.down.to.point.bottomright.curvepath"
                                        : "figure.run"
                            )

                            Label(
                                liveGhostFreshness(
                                    comparison
                                        .updatedAt
                                ),
                                systemImage:
                                    "clock"
                            )

                            if comparison
                                .isRouteAware,
                               let own =
                                comparison
                                    .ownRouteProgressPercent,
                               let opponent =
                                comparison
                                    .opponentRouteProgressPercent {
                                Text(
                                    String(
                                        format:
                                            "%.1f%% / %.1f%%",
                                        own,
                                        opponent
                                    )
                                )
                                .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Text(
                                "Waiting for the runner's next live position…"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        NavigationLink {
                            ATHLTHLiveWorkoutMapView(
                                session: session
                            )
                        } label: {
                            Label(
                                "Live map",
                                systemImage:
                                    "map.fill"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.bordered)

                        Button {
                            realtime
                                .selectLiveGhost(
                                    nil
                                )
                        } label: {
                            Label(
                                "Stop Ghost",
                                systemImage:
                                    "xmark.circle"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func liveGhostOpponentName(
        _ session:
            ATHLTHLiveWorkoutSession
    ) -> String {
        social.visibleProfiles
            .first {
                $0.userID ==
                    session.ownerID
            }?
            .resolvedName ??
        social.following
            .first {
                $0.userID ==
                    session.ownerID
            }?
            .resolvedName ??
        session.title
    }

    private func signedDistanceText(
        _ meters: Double
    ) -> String {
        let prefix =
            meters >= 0 ? "+" : "−"
        return String(
            format:
                "%@%.0f m",
            prefix,
            abs(meters)
        )
    }

    private func signedTimeText(
        _ seconds: TimeInterval
    ) -> String {
        let prefix =
            seconds >= 0 ? "+" : "−"
        let absolute =
            abs(seconds)

        if absolute >= 60 {
            let total =
                Int(
                    absolute.rounded()
                )
            return String(
                format:
                    "%@%d:%02d",
                prefix,
                total / 60,
                total % 60
            )
        }

        return String(
            format:
                "%@%.0f s",
            prefix,
            absolute
        )
    }

    private func liveGhostFreshness(
        _ date: Date
    ) -> String {
        let seconds =
            max(
                Int(
                    Date()
                        .timeIntervalSince(
                            date
                        )
                        .rounded()
                ),
                0
            )

        return seconds < 5
            ? "Now"
            : "\(seconds)s ago"
    }

    @ViewBuilder
    private var header: some View {
        if let snapshot = mirroring.snapshot {
            ATHLTHUnifiedCard {
                HStack(spacing: 14) {
                    Image(systemName: snapshot.kind.systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.kind.title)
                            .font(.title2.weight(.bold))

                        Text(ATHLTHLocalization.choose(english: "Live from Apple Watch", norwegian: "Direkte fra Apple Watch"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Circle()
                        .fill(
                            mirroring.hasActiveMirroredWorkout
                                ? ATHLTHTheme.accent
                                : Color.secondary
                        )
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    @ViewBuilder
    private func runningDashboard(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> some View {
        let hierarchy = ATHLTHPhoneLiveHierarchyResolver.resolve(
            kind: snapshot.kind
        )
        let walkFirst = hierarchy.primary == .distance
        let freshPace = ATHLTHCoachSensorFreshness.validPace(
            snapshot.currentPaceSecondsPerKilometer,
            sampledAt: snapshot.coachPaceSampleAt
        )
        let currentPace = freshPace
            ? snapshot.currentPaceSecondsPerKilometer : nil
        let averagePace = averageRunningPaceText(snapshot)
        // Never substitute whole-workout average for "current pace".
        let paceLabel = ATHLTHLocalization.choose(
            english: "CURRENT PACE", norwegian: "TEMPO NÅ")
        let paceValue = (currentPace ?? rollingPaceSeconds).map(paceText) ?? "—"
        let distance = snapshot.distanceMeters.isFinite
            ? max(snapshot.distanceMeters, 0) : 0

        return VStack(spacing: 12) {
            if snapshot.runningStepTitle != nil,
               snapshot.runningStepCount != nil {
                ATHLTHMirroredRunIntervalHero(snapshot: snapshot)
                    .id(snapshot.runningStepIndex)
                    .animation(.easeInOut(duration: 0.28),
                               value: snapshot.runningStepIndex)
            } else {
            ATHLTHUnifiedCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(
                            walkFirst
                                ? ATHLTHLocalization.choose(
                                    english: "WALKING", norwegian: "GÅTUR"
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "RUNNING", norwegian: "LØPING"
                                  ),
                            systemImage: walkFirst ? "figure.walk" : "figure.run"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Spacer(minLength: 5)

                        Label(
                            statusTitle(snapshot.state),
                            systemImage: statusIcon(snapshot.state)
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(snapshot.state))
                    }

                    if let step = snapshot.runningStepTitle,
                       !step.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: "timer")
                                .foregroundStyle(ATHLTHTheme.accent)
                            Text(step)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let index = snapshot.runningStepIndex,
                               let count = snapshot.runningStepCount,
                               count > 0 {
                                Text("\(min(max(index + 1, 1), count))/\(count)")
                                    .monospacedDigit()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        if snapshot.runningAwaitingMainStart == true {
                            Label(ATHLTHLocalization.choose(
                                english: "Ready for main section",
                                norwegian: "Klar for hoveddel"
                            ), systemImage: "figure.run.circle.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        } else if let remaining = snapshot.runningStepRemainingSeconds,
                           remaining.isFinite {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(durationText(remaining))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text(ATHLTHLocalization.choose(
                                    english: "remaining", norwegian: "igjen"
                                ))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }

                        if let progress = snapshot.runningStepProgress,
                           progress.isFinite {
                            Text(ATHLTHLocalization.choose(
                                english: "CURRENT PHASE", norwegian: "AKTIV DEL"
                            ))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            ProgressView(value: min(max(progress, 0), 1))
                                .tint(ATHLTHTheme.accent)
                        }
                        if let overall = snapshot.runningOverallProgress,
                           overall.isFinite {
                            Text(ATHLTHLocalization.choose(
                                english: "FULL WORKOUT", norwegian: "HELE ØKTEN"
                            ))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            ProgressView(value: min(max(overall, 0), 1))
                                .tint(ATHLTHTheme.accentDeep)
                        }
                        if let target = snapshot.runningStepTargetPaceSecondsPerKilometer,
                           target.isFinite, target > 0 {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Target pace", norwegian: "Måltempo"
                                ) + " · " + durationText(target) + "/km",
                                systemImage: "speedometer"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        if let incline = snapshot.runningStepTargetTreadmillInclinePercent,
                           incline.isFinite {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Planned incline", norwegian: "Planlagt stigning"
                                ) + " · " + String(format: "%.1f %%", incline),
                                systemImage: "mountain.2"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }

                    Text(
                        walkFirst
                            ? ATHLTHLocalization.choose(
                                english: "DISTANCE", norwegian: "DISTANSE"
                              )
                            : paceLabel
                    )
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(
                            walkFirst
                                ? String(format: "%.2f", distance / 1_000)
                                : paceValue
                        )
                        .font(.system(size: 67, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(walkFirst ? "km" : "/km")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    Text(
                        snapshot.treadmillInclinePercent != nil
                            ? ATHLTHLocalization.choose(
                                english: "Live from Watch · treadmill",
                                norwegian: "Direkte fra klokke · tredemølle"
                              )
                            : mirroring.connectionText
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            }

            if snapshot.routeTitle != nil || snapshot.routeCueEnglish != nil {
                ATHLTHUnifiedCard {
                    HStack(spacing: 12) {
                        Image(systemName: snapshot.routeCueSymbol ?? "arrow.up")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(
                                snapshot.routeCueOffRoute == true
                                    ? Color.orange : ATHLTHPlanDesign.accentInk
                            )
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.routeCueOffRoute == true
                                ? ATHLTHLocalization.choose(
                                    english: "BACK TO ROUTE",
                                    norwegian: "TILBAKE TIL RUTEN"
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "NEXT TURN",
                                    norwegian: "NESTE SVING"
                                  ))
                                .font(.caption2.weight(.bold))
                                .tracking(1)
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                            Text(
                                ATHLTHLocalization.isNorwegian
                                    ? (snapshot.routeCueNorwegian ??
                                        "Følg den markerte ruten.")
                                    : (snapshot.routeCueEnglish ??
                                        "Follow the highlighted route.")
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                            if let distance = snapshot.routeCueDistanceMeters {
                                Text(String(format: "%.0f m", distance))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }

            if snapshot.routeCanReturnToStart == true {
                Button {
                    _ = mirroring.requestRunBackToStart()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Continue running back to start",
                            norwegian: "Fortsett å løpe tilbake til start"
                        ),
                        systemImage: "arrow.uturn.backward"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .background(
                        ATHLTHPlanDesign.accentInk,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Keeps the Watch workout running and reverses route guidance",
                    norwegian: "Beholder Watch-økten og snur navigasjonen tilbake"
                ))
            }

            HStack(spacing: 10) {
                runningMetric(
                    title: walkFirst ? paceLabel : ATHLTHLocalization.choose(
                        english: "DISTANCE", norwegian: "DISTANSE"
                    ),
                    value: walkFirst
                        ? paceValue : String(format: "%.2f", distance / 1_000),
                    unit: walkFirst ? "/km" : "km"
                )

                ATHLTHUnifiedCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "ELAPSED", norwegian: "TID"
                        ))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(durationText(displayedElapsedTime(
                                snapshot: snapshot, now: context.date
                            )))
                            .font(.system(size: 31, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "Workout time", norwegian: "Økttid"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92,
                           alignment: .leading)
                }
            }

            HStack(spacing: 10) {
                runningMetric(
                    title: ATHLTHLocalization.choose(
                        english: "WORKOUT AVERAGE", norwegian: "SNITTEMPO ØKTEN"),
                    value: averagePace,
                    unit: "/km"
                )
                if snapshot.treadmillInclinePercent != nil &&
                   snapshot.runningStepTitle == nil {
                    Button {
                        targetPaceDraftSeconds =
                            snapshot.treadmillTargetPaceSecondsPerKilometer ??
                            enteredTargetPaceSeconds ?? 330
                        showingTargetPaceEditor = true
                    } label: {
                        runningMetric(
                            title: ATHLTHLocalization.choose(
                                english: "TARGET PACE", norwegian: "MÅLTEMPO"),
                            value: (snapshot.treadmillTargetPaceSecondsPerKilometer ??
                                    enteredTargetPaceSeconds).map(paceText) ?? "Legg inn",
                            unit: "/km"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                let heartFresh = ATHLTHCoachSensorFreshness.validHeartRate(
                    snapshot.heartRate,
                    sampledAt: snapshot.coachHeartRateSampleAt
                )
                runningMetric(
                    title: ATHLTHLocalization.choose(
                        english: "HEART RATE", norwegian: "PULS"
                    ),
                    value: heartFresh
                        ? "\(Int(snapshot.heartRate.rounded()))" : "—",
                    unit: "bpm"
                )

                if let incline = snapshot.treadmillInclinePercent {
                    Button {
                        treadmillInclineDraft = incline
                        showingTreadmillInclineEditor = true
                    } label: {
                        runningMetric(
                            title: ATHLTHLocalization.choose(
                                english: "INCLINE", norwegian: "STIGNING"
                            ),
                            value: String(format: "%.1f", incline),
                            unit: "%"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        ATHLTHLocalization.choose(
                            english: "Adjust treadmill incline",
                            norwegian: "Juster stigning"
                        )
                    )
                }
            }

            if let zone = snapshot.runningStepTargetHeartRateZone,
               (1...5).contains(zone) {
                HStack(spacing: 7) {
                    Text(ATHLTHLocalization.choose(
                        english: "TARGET HEART RATE", norwegian: "PULSMÅL"
                    ) + " · " + ATHLTHLocalization.choose(
                        english: "Zone", norwegian: "Sone"
                    ) + " \(zone)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    ForEach(1...5, id: \.self) { number in
                        Capsule()
                            .fill(number == zone
                                  ? ATHLTHTheme.accent : ATHLTHTheme.divider)
                            .frame(width: 15, height: 7)
                    }
                }
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            if snapshot.runningManualAdvanceRequired == true,
               snapshot.state == .running,
               let stepIndex = snapshot.runningStepIndex {
                Button {
                    mirroring.advanceRunningStep(
                        expectedIndex: stepIndex, startedAt: snapshot.startedAt,
                        startMain: snapshot.runningAwaitingMainStart == true
                    )
                } label: {
                    Label(
                        snapshot.runningAwaitingMainStart == true
                            ? ATHLTHLocalization.choose(
                                english: "Start main section", norwegian: "Start hoveddel"
                              )
                            : snapshot.runningStepPhase == "warmup"
                            ? ATHLTHLocalization.choose(
                                english: "End warm-up", norwegian: "Avslutt oppvarming"
                              )
                            : snapshot.runningStepPhase == "cooldown"
                            ? ATHLTHLocalization.choose(
                                english: "End cool-down", norwegian: "Avslutt nedjogging"
                              )
                            : ATHLTHLocalization.choose(
                                english: "Next phase", norwegian: "Neste del"
                              ),
                        systemImage: "arrow.right.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
            }

            if let next = snapshot.runningNextStepTitle, !next.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Next: \(next)", norwegian: "Neste: \(next)"
                    ),
                    systemImage: "arrow.forward.circle"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func mirroredOtherSportHeader(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> some View {
        if snapshot.kind != .strength {
            let measuredCycling =
                ATHLTHOtherSportLiveResolver.resolve(
                    kind: snapshot.kind,
                    distanceMeters: snapshot.distanceMeters
                ) == .measuredDistance

            ATHLTHUnifiedCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        Label(
                            snapshot.kind.title,
                            systemImage: snapshot.kind.systemImage
                        )
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Spacer(minLength: 0)

                        TimelineView(.periodic(from: .now, by: 5)) { tick in
                            let delayed = snapshot.state == .running &&
                                !ATHLTHPhoneMirroredClock.isFresh(
                                    snapshotAt: snapshot.capturedAt,
                                    now: tick.date
                                )
                            Label(
                                delayed
                                    ? ATHLTHLocalization.choose(
                                        english: "Delayed",
                                        norwegian: "Forsinket"
                                      )
                                    : statusTitle(snapshot.state),
                                systemImage: delayed
                                    ? "wifi.exclamationmark"
                                    : statusIcon(snapshot.state)
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                delayed
                                    ? Color.orange
                                    : statusColor(snapshot.state)
                            )
                            .lineLimit(1)
                        }
                    }

                    if !measuredCycling {
                        Text(ATHLTHLocalization.choose(
                            english: "WORKOUT TIME", norwegian: "ØKTTID"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Text(durationText(displayedElapsedTime(
                                snapshot: snapshot, now: tick.date
                            )))
                            .font(.system(size: 62, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.60)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        }

                        Text(otherSportSubtitle(snapshot.kind))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        Text(otherSportSubtitle(snapshot.kind))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func otherSportSubtitle(_ kind: WatchWorkoutKind) -> String {
        switch kind {
        case .hiit:
            return ATHLTHLocalization.choose(
                english: "High-intensity session",
                norwegian: "Høyintensiv økt"
            )
        case .functional:
            return ATHLTHLocalization.choose(
                english: "Functional training",
                norwegian: "Funksjonell trening"
            )
        case .rowing:
            return ATHLTHLocalization.choose(
                english: "Rowing workout",
                norwegian: "Roøkt"
            )
        case .stairClimbing:
            return ATHLTHLocalization.choose(
                english: "Stair climbing",
                norwegian: "Trappetrening"
            )
        case .yoga:
            return ATHLTHLocalization.choose(
                english: "Yoga session", norwegian: "Yogaøkt"
            )
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Cycling workout", norwegian: "Sykkeløkt"
            )
        case .other, .running, .walking, .strength:
            return ATHLTHLocalization.choose(
                english: "Workout", norwegian: "Treningsøkt"
            )
        }
    }

    private func mirroredCyclingDistance(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> some View {
        ATHLTHUnifiedCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(ATHLTHLocalization.choose(
                    english: "RECORDED DISTANCE",
                    norwegian: "MÅLT DISTANSE"
                ))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(String(
                        format: "%.2f",
                        max(snapshot.distanceMeters, 0) / 1_000
                    ))
                        .font(.system(size: 62, weight: .bold,
                                      design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                    Text("km")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Label(
                        durationText(displayedElapsedTime(
                            snapshot: snapshot, now: timeline.date
                        )),
                        systemImage: "clock"
                    )
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func mirroredStrengthSummary(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> some View {
        if let exercise = snapshot.strengthExerciseName {
            ATHLTHUnifiedCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "CURRENT EXERCISE",
                            norwegian: "AKTUELL ØVELSE"
                        ),
                        systemImage: "dumbbell.fill"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                    Text(exercise)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)

                    if snapshot.state == .running {
                        TimelineView(.periodic(from: .now, by: 5)) { timeline in
                            if !ATHLTHPhoneMirroredClock.isFresh(
                                snapshotAt: snapshot.capturedAt,
                                now: timeline.date
                            ) {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Watch data delayed",
                                        norwegian: "Klokkedata forsinket"
                                    ),
                                    systemImage: "wifi.exclamationmark"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            }
                        }
                    }

                    if let ends = snapshot.strengthRestEndsAt {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let remaining = max(ends.timeIntervalSince(timeline.date), 0)
                            Text(remaining > 0
                                ? durationText(remaining)
                                : ATHLTHLocalization.choose(
                                    english: "READY", norwegian: "KLAR"
                                  ))
                                .font(.system(size: 44, weight: .bold,
                                              design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHTheme.primaryText)
                        }
                    } else if let reps = snapshot.strengthReps {
                        Text("\(reps) reps")
                            .font(.system(size: 43, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                    }

                    HStack {
                        if let index = snapshot.strengthSetIndex,
                           let count = snapshot.strengthSetCount,
                           count > 0 {
                            Text(ATHLTHLocalization.choose(
                                english: "Set \(min(max(index + 1, 1), count)) of \(count)",
                                norwegian: "Sett \(min(max(index + 1, 1), count)) av \(count)"
                            ))
                        }
                        Spacer(minLength: 0)
                        if let weight = snapshot.strengthWeightKilograms {
                            Text(String(format: "%.1f kg", weight))
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func runningMetric(
        title: String,
        value: String,
        unit: String
    ) -> some View {
        ATHLTHUnifiedCard {
            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(title)
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .tracking(1.15)
                    .foregroundStyle(
                        .secondary
                    )

                Spacer(
                    minLength: 3
                )

                Text(value)
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .minimumScaleFactor(
                        0.65
                    )
                    .lineLimit(1)

                Text(unit)
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        .secondary
                    )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 92,
                alignment: .leading
            )
        }
    }

    private func runningPaceText(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> String {
        if let pace = snapshot.currentPaceSecondsPerKilometer,
           pace.isFinite,
           pace > 0 {
            return paceText(pace)
        }

        // Indoor runs have no GPS speed. Prefer the measured average pace
        // when Watch distance and elapsed time are available.
        return averageRunningPaceText(snapshot)
    }

    /// 15–30-second rolling pace derived from measured Watch distance deltas.
    /// Paused samples and stale/implausible jumps never change the live value.
    private func updateRollingPace(with snapshot: WatchWorkoutLiveSnapshot) {
        guard snapshot.kind == .running || snapshot.kind == .walking else { return }
        if paceWorkoutStart != snapshot.startedAt {
            paceWorkoutStart = snapshot.startedAt
            paceSamples = []
            rollingPaceSeconds = nil
            enteredTargetPaceSeconds = nil
        }
        guard snapshot.state == .running,
              snapshot.elapsedTime.isFinite,
              snapshot.distanceMeters.isFinite, snapshot.distanceMeters >= 0
        else { return }
        let sample = (elapsed: snapshot.elapsedTime, distance: snapshot.distanceMeters)
        if let prev = paceSamples.last {
            guard sample.elapsed > prev.elapsed && sample.distance >= prev.distance else { return }
        }
        paceSamples.append(sample)
        paceSamples = paceSamples.filter { sample.elapsed - $0.elapsed <= 30 }
        guard let first = paceSamples.first,
              sample.elapsed - first.elapsed >= 8,
              sample.distance - first.distance >= 12
        else { return }
        let meters = sample.distance - first.distance
        let seconds = sample.elapsed - first.elapsed
        let pace = seconds * 1000 / meters
        if pace.isFinite, (120...1800).contains(pace) {
            rollingPaceSeconds = pace
        }
    }

    private var mirroredSpotifyBar: some View {
        HStack(spacing: 7) {
            ATHLTHSpotifyGlyph()
                .frame(width: 17, height: 17)
            Text("Spotify")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Button {
                Task {
                    await spotify.handleIPhoneAudioDockCommand(
                        spotify.isPlaying ? .pause : .resume)
                }
            } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 34)
            }
            .buttonStyle(.plain)
            Button {
                Task { await spotify.handleIPhoneAudioDockCommand(.next) }
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 32, height: 34)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(ATHLTHTrainDesign.ink)
        .padding(.horizontal, 10)
        .frame(width: 210, height: 40)
        .background(ATHLTHTrainDesign.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(
            ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.7))
    }

    private func averageRunningPaceText(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> String {
        guard let pace = ATHLTHRunningPace.average(
            elapsedSeconds: snapshot.elapsedTime,
            distanceMeters: snapshot.distanceMeters
        ) else { return "—" }

        return paceText(pace)
    }

    private func paceText(
        _ seconds:
            TimeInterval
    ) -> String {
        let total =
            max(
                Int(
                    seconds.rounded()
                ),
                0
            )
        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }

    @ViewBuilder
    private func timer(_ snapshot: WatchWorkoutLiveSnapshot) -> some View {
        ATHLTHUnifiedCard {
            VStack(spacing: 6) {
                Text(ATHLTHLocalization.choose(english: "Duration", norwegian: "Varighet"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        durationText(
                            displayedElapsedTime(
                                snapshot: snapshot,
                                now: context.date
                            )
                        )
                    )
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func metricCard(
        title: String,
        value: String,
        unit: String,
        icon: String
    ) -> some View {
        ATHLTHUnifiedCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func controls(_ snapshot: WatchWorkoutLiveSnapshot) -> some View {
        if snapshot.state == .completed || snapshot.state == .failed {
            Button {
                mirroring.dismissSummary()
                if ghostRace.reference != nil {
                    ghostRace.dismissResult()
                }
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ATHLTHTheme.accent)
        } else {
            HStack(spacing: 12) {
                Button {
                    mirroring.sendCommand(
                        snapshot.state == .paused ? .resume : .pause
                    )
                } label: {
                    Label(
                        snapshot.state == .paused ? "Resume" : "Pause",
                        systemImage: snapshot.state == .paused
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(
                    snapshot.state == .preparing ||
                    snapshot.state == .ending
                )

                Button(role: .destructive) {
                    mirroring.sendCommand(.end)
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(snapshot.state == .ending)
            }
        }
    }

    private func displayedElapsedTime(
        snapshot: WatchWorkoutLiveSnapshot,
        now: Date
    ) -> TimeInterval {
        guard snapshot.state == .running else {
            return snapshot.elapsedTime
        }

        return max(
            snapshot.elapsedTime,
            snapshot.elapsedTime + now.timeIntervalSince(snapshot.capturedAt)
        )
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func statusTitle(
        _ state: WatchWorkoutMirrorState
    ) -> String {
        switch state {
        case .preparing: return "Starting"
        case .running: return "Live"
        case .paused: return "Paused"
        case .ending: return "Saving"
        case .completed: return "Completed"
        case .failed: return "Error"
        }
    }

    private func statusIcon(
        _ state: WatchWorkoutMirrorState
    ) -> String {
        switch state {
        case .preparing: return "hourglass"
        case .running: return "waveform.path.ecg"
        case .paused: return "pause.circle.fill"
        case .ending: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(
        _ state: WatchWorkoutMirrorState
    ) -> Color {
        switch state {
        case .running, .completed:
            return ATHLTHTheme.accent
        case .paused, .preparing, .ending:
            return .orange
        case .failed:
            return .red
        }
    }
    @MainActor
    private func syncLivePosition() async {
        guard let snapshot =
                mirroring.snapshot
        else {
            return
        }

        if snapshot.state == .completed ||
            snapshot.state == .failed {
            if realtime.currentSession != nil {
                await realtime
                    .leaveCurrentLiveWorkout()
            }
            return
        }

        guard snapshot.state == .running ||
                snapshot.state == .paused
        else {
            return
        }

        if realtime.currentSession == nil {
            guard social.privacy?
                    .shareLiveWorkoutLocation ==
                    true
            else {
                return
            }

            let activity: String
            switch snapshot.kind {
            case .walking:
                activity = "walking"
            case .cycling:
                activity = "cycling"
            case .running:
                activity = "running"
            default:
                return
            }

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title:
                        snapshot.routeTitle ??
                        snapshot.kind.title,
                    activity: activity,
                    visibility: visibility,
                    routeKey:
                        snapshot
                            .routeComparisonID,
                    routeDistanceMeters:
                        snapshot
                            .routeDistanceMeters,
                    routeTitle:
                        snapshot
                            .routeTitle
                )
        }

        await realtime
            .publishMirroredSnapshot(
                snapshot,
                includeHeartRate:
                    social.privacy?
                        .shareLiveWorkoutHeartRate ==
                    true
            )
    }

}
