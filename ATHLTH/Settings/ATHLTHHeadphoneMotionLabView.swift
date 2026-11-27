import AVFoundation
import Combine
@preconcurrency import CoreMotion
import SwiftUI

/// A bounded, deterministic prototype, not a clinical or gait classifier.
/// Pitch excursions are relative to the initial pose; wrap at +/- pi.
struct ATHLTHHeadMotionLabAccumulator {
    private(set) var count = 0
    private(set) var squaredAcceleration = 0.0
    private(set) var squaredRotation = 0.0
    private(set) var candidateNods = 0
    private var baseline: Double?
    private var excursionAt: Double?
    private var lastNodAt = -Double.infinity
    private var lastTimestamp = -Double.infinity

    mutating func ingest(timestamp: Double, pitch: Double, accelerationMagnitude: Double, rotationMagnitude: Double) {
        guard timestamp.isFinite, timestamp > lastTimestamp, pitch.isFinite,
              accelerationMagnitude.isFinite, rotationMagnitude.isFinite,
              (0...20).contains(accelerationMagnitude), (0...50).contains(rotationMagnitude) else { return }
        if timestamp - lastTimestamp > 0.5 {
            baseline = nil
            excursionAt = nil
        }
        lastTimestamp = timestamp
        count += 1
        squaredAcceleration += accelerationMagnitude * accelerationMagnitude
        squaredRotation += rotationMagnitude * rotationMagnitude
        if baseline == nil { baseline = pitch }
        guard let baseline else { return }
        let delta = abs(atan2(sin(pitch - baseline), cos(pitch - baseline)))
        if let excursionAt {
            let elapsed = timestamp - excursionAt
            if elapsed > 1.2 {
                self.excursionAt = nil
                self.baseline = pitch
            } else if delta < 0.12 {
                if elapsed >= 0.15, timestamp - lastNodAt >= 1.5 {
                    candidateNods += 1
                    lastNodAt = timestamp
                }
                self.excursionAt = nil
            }
        } else if delta > 0.32 {
            excursionAt = timestamp
        }
    }

    var accelerationRMS: Double? { count > 0 ? sqrt(squaredAcceleration / Double(count)) : nil }
    var rotationRMS: Double? { count > 0 ? sqrt(squaredRotation / Double(count)) : nil }
}

struct ATHLTHHeadphoneMotionLabView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("athlth.airpods.recognizedAudioRoute") private var recognizedUID = ""
    @State private var runID: UUID?
    @State private var progress = 0
    @State private var status = ""
    @State private var activity = ""
    @State private var summary: ATHLTHHeadMotionLabAccumulator?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var eligible: Bool {
        session.signedIn && !session.previewModeEnabled && session.currentRole.canAccessControlCenter
    }

    var body: some View {
        ATHLTHSettingsScreen(title: tr("Headphone sensor lab", "Sensorlab for hodetelefoner"),
            subtitle: tr("Experimental · local only", "Eksperimentelt · kun lokalt")) {
            ATHLTHSettingsGroup(title: tr("20-second test", "20-sekunders test")) {
                PremiumSettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Wear compatible AirPods. Stay in a safe place, keep your head neutral initially, and try a small deliberate nod. Activity and motion availability are checked separately.", "Bruk kompatible AirPods. Stå på et trygt sted, hold hodet nøytralt først og prøv et lite, bevisst nikk. Aktivitets- og bevegelsestilgang sjekkes separat."))
                            .font(.footnote).foregroundStyle(ATHLTHTheme.mutedText)
                        if runID != nil {
                            ProgressView(value: Double(progress), total: 20)
                            Button(tr("Stop test", "Stopp test"), role: .cancel) { cancel() }
                        } else {
                            Button(tr("Start local test", "Start lokal test")) {
                                summary = nil
                                activity = ""
                                progress = 0
                                status = ""
                                runID = UUID()
                            }
                            .disabled(!eligible || scenePhase != .active ||
                                !ATHLTHAirPodsRoute.current().isRecognized(rememberedUID: recognizedUID) ||
                                ATHLTHWorkoutRecordingArbiter.hasPendingLaunch)
                        }
                        if !status.isEmpty { Text(status).font(.footnote) }
                        if !activity.isEmpty {
                            Label(activity, systemImage: "figure.walk")
                                .font(.subheadline)
                        }
                    }.padding(14)
                }
            }
            if let summary {
                ATHLTHSettingsGroup(title: tr("Motion observations", "Bevegelsesobservasjoner")) {
                    PremiumSettingsCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(tr("Unique samples", "Unike målinger") + ": " + String(summary.count))
                            if let value = summary.accelerationRMS {
                                Text(tr("Acceleration RMS", "Akselerasjon RMS") + ": " + String(format: "%.3f g", value))
                            }
                            if let value = summary.rotationRMS {
                                Text(tr("Rotation RMS", "Rotasjon RMS") + ": " + String(format: "%.3f rad/s", value))
                            }
                            Text(tr("Possible nods", "Mulige nikk") + ": " + String(summary.candidateNods))
                            Text(tr("These are descriptive head-motion signals and possible gestures, not step cadence, running form, fatigue, or validated AI predictions. No gesture changes a workout.", "Dette er beskrivende hodebevegelser og mulige gester, ikke stegfrekvens, løpeteknikk, utmattelse eller validerte AI-prediksjoner. Ingen gest endrer en økt."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        }.font(.subheadline.monospacedDigit()).padding(14)
                    }
                }
            }
        }
        .task(id: runID) {
            guard let id = runID else { return }
            await run(id)
        }
        .onDisappear { cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .onChange(of: eligible) { _, allowed in if !allowed { cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in cancel() }
    }

    private func cancel() {
        if runID != nil {
            runID = nil
            status = tr("Test stopped", "Test stoppet")
        }
    }

    @MainActor
    private func run(_ id: UUID) async {
        let motion = CMHeadphoneMotionManager()
        let classifier = CMHeadphoneActivityManager()
        let route = ATHLTHAirPodsRoute.current()
        guard eligible, scenePhase == .active, route.isRecognized(rememberedUID: recognizedUID) else {
            cancel()
            return
        }
        let motionAllowed = motion.isDeviceMotionAvailable &&
            CMHeadphoneMotionManager.authorizationStatus() != .denied &&
            CMHeadphoneMotionManager.authorizationStatus() != .restricted
        let activityAllowed = classifier.isActivityAvailable && classifier.isStatusAvailable &&
            CMHeadphoneActivityManager.authorizationStatus() != .denied &&
            CMHeadphoneActivityManager.authorizationStatus() != .restricted
        defer {
            motion.stopDeviceMotionUpdates()
            classifier.stopActivityUpdates()
        }
        guard motionAllowed || activityAllowed else {
            status = tr("Sensors unavailable or permission denied", "Sensorer utilgjengelige eller tillatelse avslått")
            runID = nil
            return
        }
        if motionAllowed { motion.startDeviceMotionUpdates() }
        if activityAllowed {
            classifier.startActivityUpdates(to: .main) { sample, _ in
                guard let sample else { return }
                let category: Int
                if sample.confidence == .low { category = 0 }
                else if sample.running { category = 1 }
                else if sample.walking { category = 2 }
                else if sample.stationary { category = 3 }
                else if sample.cycling { category = 4 }
                else { category = 0 }
                Task { @MainActor in
                    guard runID == id else { return }
                    switch category {
                    case 1: activity = tr("Apple activity: running", "Apple-aktivitet: løping")
                    case 2: activity = tr("Apple activity: walking", "Apple-aktivitet: gange")
                    case 3: activity = tr("Apple activity: stationary", "Apple-aktivitet: stillstand")
                    case 4: activity = tr("Apple activity: cycling", "Apple-aktivitet: sykling")
                    default: activity = tr("Apple activity: uncertain", "Apple-aktivitet: usikker")
                    }
                }
            }
        } else {
            activity = tr("Activity classification unavailable", "Aktivitetsklassifisering utilgjengelig")
        }
        status = tr("Collecting local observations", "Samler lokale observasjoner")
        var accumulator = ATHLTHHeadMotionLabAccumulator()
        for tick in 0..<200 {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard !Task.isCancelled, runID == id, eligible, scenePhase == .active,
                  route == ATHLTHAirPodsRoute.current() else { cancel(); return }
            if motionAllowed, let sample = motion.deviceMotion {
                let a = sample.userAcceleration
                let r = sample.rotationRate
                accumulator.ingest(timestamp: sample.timestamp, pitch: sample.attitude.pitch,
                    accelerationMagnitude: sqrt(a.x*a.x + a.y*a.y + a.z*a.z),
                    rotationMagnitude: sqrt(r.x*r.x + r.y*r.y + r.z*r.z))
            }
            if tick % 10 == 9 { progress = (tick + 1) / 10 }
        }
        guard runID == id else { return }
        summary = accumulator.count > 0 ? accumulator : nil
        status = accumulator.count > 0
            ? tr("Local test complete", "Lokal test fullført")
            : tr("No motion samples received", "Ingen bevegelsesmålinger mottatt")
        runID = nil
    }
}
