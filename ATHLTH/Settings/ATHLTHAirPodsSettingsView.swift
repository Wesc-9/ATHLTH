import AVFoundation
import Combine
import CoreMotion
import SwiftUI
import UIKit

/// Reports the selected audio route, not the list of paired Bluetooth devices.
/// Device names can be changed by the user and never prove sensor support.
struct ATHLTHAirPodsRoute: Equatable {
    let name: String?
    let uid: String?

    static func current() -> Self {
        let port = AVAudioSession.sharedInstance().currentRoute.outputs.first {
            [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
        return Self(name: port?.portName, uid: port?.uid)
    }

    func isRecognized(rememberedUID: String) -> Bool {
        guard let uid, !uid.isEmpty else { return false }
        return name?.localizedCaseInsensitiveContains("AirPods") == true ||
            (!rememberedUID.isEmpty && uid == rememberedUID)
    }
}

struct ATHLTHAirPodsSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("athlth.airpods.recognizedAudioRoute") private var recognizedUID = ""
    @AppStorage("athlth.airpods.liveSensorPilot") private var liveSensorPilot = false
    @State private var route = ATHLTHAirPodsRoute.current()
    @State private var motionTestID: UUID?
    @State private var motionResult = MotionResult.unchecked

    private enum MotionResult {
        case unchecked, testing, measured, unavailable, noSample, denied
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var recognized: Bool { route.isRecognized(rememberedUID: recognizedUID) }

    var body: some View {
        ATHLTHSettingsScreen(title: "AirPods",
            subtitle: tr("Audio and model-dependent training sensors", "Lyd og modellavhengige treningssensorer")) {
            ATHLTHSettingsGroup(title: tr("Connection", "Tilkobling")) {
                PremiumSettingsCard {
                    PremiumSettingsRow(icon: "airpodspro", iconTint: ATHLTHTheme.accentDeep,
                        title: route.name ?? "AirPods",
                        subtitle: recognized
                            ? tr("Selected audio output", "Valgt lydutgang")
                            : tr("AirPods not identified on the current route", "AirPods er ikke identifisert som valgt lydutgang")) {
                        ATHLTHAudioRouteControl(compact: true)
                    }
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Pair any generation of AirPods in the device Bluetooth settings. Select them as audio output above. ATHLTH does not need a separate Bluetooth pairing.", "Koble sammen valgfri AirPods-generasjon i enhetens Bluetooth-innstillinger. Velg dem som lydutgang ovenfor. ATHLTH trenger ingen egen Bluetooth-sammenkobling."))
                        if !recognized, let uid = route.uid {
                            Button(tr("Remember this renamed AirPods", "Husk disse AirPods med endret navn")) {
                                recognizedUID = uid
                            }
                        }
                        if !recognizedUID.isEmpty {
                            Button(tr("Forget manually identified AirPods", "Glem manuelt identifiserte AirPods"), role: .destructive) {
                                recognizedUID = ""
                            }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .padding(12)
                }
            }
            ATHLTHSettingsGroup(title: tr("Available features", "Tilgjengelige funksjoner")) {
                PremiumSettingsCard {
                    feature("waveform", "Audio Coach", recognized
                        ? tr("Uses system audio output", "Bruker systemets lydutgang")
                        : tr("Select your AirPods first", "Velg AirPods først"))
                    SettingsDivider()
                    feature("mic", tr("Siri and voice", "Siri og stemme"),
                        tr("Existing Siri shortcuts and optional voice Coach; no always-on microphone.", "Eksisterende Siri-snarveier og valgfri stemmecoach; ingen kontinuerlig mikrofon."))
                    SettingsDivider()
                    feature("heart", tr("Heart rate", "Puls"),
                        tr("AirPods Pro 3 have a heart-rate sensor. Older models do not. Live sensor delivery must be verified in a supported HealthKit workout; the audio route cannot confirm it.", "AirPods Pro 3 har pulssensor. Eldre modeller har ikke dette. Live puls må verifiseres i en støttet HealthKit-økt; lydutgangen kan ikke bekrefte det."))
                    SettingsDivider()
                    if #available(iOS 26.0, *) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(tr("Live heart rate (beta)", "Livepuls (beta)"), isOn: $liveSensorPilot)
                            Text(tr("Optional for new phone-recorded running and walking workouts. Requires Apple Health workout and heart-rate access and a compatible sensor. No change to Watch workouts. Missing readings remain unavailable.", "Valgfritt for nye løpe- og gåøkter registrert på telefon. Krever Apple Helse-tilgang til økter og puls samt kompatibel sensor. Endrer ikke Watch-økter. Manglende målinger vises som utilgjengelige."))
                                .font(.caption).foregroundStyle(ATHLTHTheme.mutedText)
                        }.padding(12)
                        SettingsDivider()
                    }
                    feature("gyroscope", tr("Motion", "Bevegelse"), motionStatus)
                    VStack(alignment: .leading, spacing: 8) {
                        Button(tr("Test motion sensor", "Test bevegelsessensor")) {
                            motionResult = .testing
                            motionTestID = UUID()
                        }
                        .disabled(!recognized || motionTestID != nil)
                        Text(tr("Optional local test, up to three seconds. Wear your AirPods. No measurements are retained.", "Valgfri lokal test, inntil tre sekunder. Ha AirPods i ørene. Ingen målinger lagres."))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }.padding(12)
                }
            }
        }
        .onAppear { refreshRoute() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
            refreshRoute()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshRoute() }
            else { cancelTest() }
        }
        .onDisappear { cancelTest() }
        .task(id: motionTestID) {
            guard let testID = motionTestID else { return }
            await runMotionTest(testID)
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        PremiumSettingsRow(icon: icon, iconTint: ATHLTHTheme.accentDeep, title: title, subtitle: detail) {
            EmptyView()
        }
    }

    private var motionStatus: String {
        switch motionResult {
        case .unchecked: return tr("Not tested", "Ikke testet")
        case .testing: return tr("Testing…", "Tester…")
        case .measured: return tr("Motion sample received", "Bevegelsesdata mottatt")
        case .unavailable: return tr("Not available on this connection", "Ikke tilgjengelig på denne tilkoblingen")
        case .noSample: return tr("No sample received; check fit and permissions", "Ingen måling mottatt; sjekk passform og tillatelser")
        case .denied: return tr("Motion permission denied or restricted", "Bevegelsestillatelse avslått eller begrenset")
        }
    }

    private func refreshRoute() {
        let next = ATHLTHAirPodsRoute.current()
        if route != next {
            cancelTest()
            motionResult = .unchecked
            route = next
        }
    }

    private func cancelTest() {
        motionTestID = nil
        if motionResult == .testing { motionResult = .unchecked }
    }

    @MainActor
    private func runMotionTest(_ testID: UUID) async {
        let manager = CMHeadphoneMotionManager()
        var result = MotionResult.noSample
        defer {
            manager.stopDeviceMotionUpdates()
            if motionTestID == testID && !Task.isCancelled {
                motionResult = result
                motionTestID = nil
            }
        }
        guard recognized else { return }
        let status = CMHeadphoneMotionManager.authorizationStatus()
        guard status != .denied && status != .restricted else {
            result = .denied
            return
        }
        guard manager.isDeviceMotionAvailable else {
            result = .unavailable
            return
        }
        manager.startDeviceMotionUpdates()
        for _ in 0..<30 {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard !Task.isCancelled, motionTestID == testID else { return }
            if manager.deviceMotion != nil {
                result = .measured
                return
            }
        }
    }
}
