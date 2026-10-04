import SwiftUI

struct HomeAssistantSettingsView: View {
    @EnvironmentObject private var homeAssistant:
        HomeAssistantConnectionStore

    @State private var manualAddress = ""
    @State private var pairingCode = ""
    @State private var showingDisconnectConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if homeAssistant.isConnected {
                    connectedCard
                    sharingCard
                } else {
                    discoveryCard
                    manualConnectionCard
                }

                securityCard

                if let error = homeAssistant.lastErrorMessage,
                   !error.isEmpty {
                    errorCard(error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
        .navigationTitle("Home Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !homeAssistant.isConnected {
                homeAssistant.startDiscovery()
            }
        }
        .onDisappear {
            homeAssistant.stopDiscovery()
        }
        .onChange(of: homeAssistant.shareWorkoutState) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareCompletedWorkouts) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareRecovery) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareTrainingLoad) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareSleep) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareHRV) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareRestingHeartRate) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareRespiratoryRate) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareWeeklyProgress) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareNextWorkout) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareTrainingCalendar) { _, _ in
            clearDisabledValues()
        }
        .onChange(of: homeAssistant.shareGoals) { _, _ in
            clearDisabledValues()
        }
        .onChange(
            of: homeAssistant.shareLiveWorkoutDetails
        ) { _, _ in
            clearDisabledValues()
        }
        .onChange(
            of: homeAssistant.shareStrengthDetails
        ) { _, _ in
            clearDisabledValues()
        }
        .onChange(
            of: homeAssistant.shareMilestoneEvents
        ) { _, _ in
            clearDisabledValues()
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Disconnect Home Assistant?",
                norwegian: "Koble fra Home Assistant?"
            ),
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Disconnect",
                    norwegian: "Koble fra"
                ),
                role: .destructive
            ) {
                Task {
                    await homeAssistant.disconnect()
                    homeAssistant.startDiscovery()
                }
            }

            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel",
                    norwegian: "Avbryt"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "ATHLTH will remove the Home Assistant pairing from this device.",
                    norwegian:
                        "ATHLTH fjerner Home Assistant-paringen fra denne enheten."
                )
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        Color(
                            red: 0.12,
                            green: 0.58,
                            blue: 0.86
                        )
                        .opacity(0.12)
                    )
                    .frame(width: 62, height: 62)

                Image(systemName: "house.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(
                        Color(
                            red: 0.12,
                            green: 0.58,
                            blue: 0.86
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Home Assistant")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Connect ATHLTH to your home without copying API keys or long-lived tokens.",
                        norwegian:
                            "Koble ATHLTH til hjemmet ditt uten å kopiere API-nøkler eller langtids-tokens."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Connected securely",
                            norwegian: "Sikkert tilkoblet"
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        homeAssistant.connectedInstanceName
                            ?? "Home Assistant"
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()
            }

            if let url = homeAssistant.connectedInstanceURL {
                HStack(spacing: 9) {
                    Image(systemName: "network")
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                connectionDetail(
                    icon: "key.slash",
                    title: ATHLTHLocalization.choose(
                        english: "No API key stored",
                        norwegian: "Ingen API-nøkkel lagret"
                    )
                )

                connectionDetail(
                    icon: "lock.shield",
                    title: ATHLTHLocalization.choose(
                        english: "Signed webhook requests",
                        norwegian: "Signerte webhook-forespørsler"
                    )
                )

                connectionDetail(
                    icon: "key.fill",
                    title: ATHLTHLocalization.choose(
                        english: "Pairing secret kept in Keychain",
                        norwegian: "Paringsnøkkel lagret i Keychain"
                    )
                )
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await homeAssistant.sendConnectionTest()
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Test connection",
                            norwegian: "Test tilkobling"
                        ),
                        systemImage: "bolt.horizontal.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    showingDisconnectConfirmation = true
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Disconnect",
                            norwegian: "Koble fra"
                        )
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var sharingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Shared with Home Assistant",
                        norwegian: "Delt med Home Assistant"
                    ),
                    systemImage: "slider.horizontal.3"
                )
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Choose exactly which ATHLTH data is sent to your Home Assistant. Health-derived metrics stay off until you enable them.",
                        norwegian:
                            "Velg nøyaktig hvilke ATHLTH-data som sendes til Home Assistant. Helsedata er av til du selv slår dem på."
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Active workout",
                    norwegian: "Aktiv økt"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Lets automations know when training starts and stops.",
                    norwegian:
                        "Lar automasjoner vite når trening starter og stopper."
                ),
                icon: "figure.run",
                isOn: $homeAssistant.shareWorkoutState
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Completed workouts",
                    norwegian: "Fullførte økter"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares workout name, type, duration and distance when available.",
                    norwegian:
                        "Deler navn, type, varighet og distanse når det finnes."
                ),
                icon: "checkmark.circle",
                isOn: $homeAssistant.shareCompletedWorkouts
            )

            sharingToggle(
                title: "Recovery",
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares ATHLTH's 0–100 recovery score. Off by default.",
                    norwegian:
                        "Deler ATHLTH sin recovery-score fra 0–100. Av som standard."
                ),
                icon: "heart.text.square",
                isOn: $homeAssistant.shareRecovery
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Training load",
                    norwegian: "Belastning"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the recent-to-baseline training load ratio. Off by default.",
                    norwegian:
                        "Deler forholdet mellom nyere og normal treningsbelastning. Av som standard."
                ),
                icon: "chart.line.uptrend.xyaxis",
                isOn: $homeAssistant.shareTrainingLoad
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Sleep duration",
                    norwegian: "Søvnvarighet"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the latest sleep duration from Apple Health. Off by default.",
                    norwegian:
                        "Deler siste søvnvarighet fra Apple Health. Av som standard."
                ),
                icon: "bed.double.fill",
                isOn: $homeAssistant.shareSleep
            )

            sharingToggle(
                title: "HRV",
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the latest heart-rate variability value in milliseconds. Off by default.",
                    norwegian:
                        "Deler siste HRV-verdi i millisekunder. Av som standard."
                ),
                icon: "waveform.path.ecg",
                isOn: $homeAssistant.shareHRV
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Resting heart rate",
                    norwegian: "Hvilepuls"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the latest resting heart-rate value. Off by default.",
                    norwegian:
                        "Deler siste registrerte hvilepuls. Av som standard."
                ),
                icon: "heart.fill",
                isOn: $homeAssistant.shareRestingHeartRate
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Respiratory rate",
                    norwegian: "Respirasjon"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the latest respiratory-rate value. Off by default.",
                    norwegian:
                        "Deler siste registrerte respirasjonsfrekvens. Av som standard."
                ),
                icon: "lungs.fill",
                isOn: $homeAssistant.shareRespiratoryRate
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Weekly progress",
                    norwegian: "Ukens fremdrift"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares progress, training minutes and distance for the current training week.",
                    norwegian:
                        "Deler fremdrift, treningsminutter og distanse for inneværende treningsuke."
                ),
                icon: "calendar.badge.checkmark",
                isOn: $homeAssistant.shareWeeklyProgress
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Next workout",
                    norwegian: "Neste økt"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the title and scheduled time of the next planned workout.",
                    norwegian:
                        "Deler navn og tidspunkt for den neste planlagte økten."
                ),
                icon: "calendar.badge.clock",
                isOn: $homeAssistant.shareNextWorkout
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Training calendar",
                    norwegian: "Treningskalender"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares upcoming planned workouts with the Home Assistant calendar. Off by default.",
                    norwegian:
                        "Deler kommende planlagte økter med Home Assistant-kalenderen. Av som standard."
                ),
                icon: "calendar",
                isOn:
                    $homeAssistant
                        .shareTrainingCalendar
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Active goal",
                    norwegian: "Aktivt mål"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares the active goal, progress and days remaining. Off by default.",
                    norwegian:
                        "Deler aktivt mål, fremdrift og dager igjen. Av som standard."
                ),
                icon: "target",
                isOn: $homeAssistant.shareGoals
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Live workout details",
                    norwegian: "Live treningsdata"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares phase, elapsed time, distance, pace/speed, heart-rate zone and treadmill incline while training. GPS coordinates are never shared. Off by default.",
                    norwegian:
                        "Deler fase, tid, distanse, tempo/fart, pulssone og møllestigning under trening. GPS-koordinater deles aldri. Av som standard."
                ),
                icon: "waveform.path.ecg.rectangle",
                isOn:
                    $homeAssistant
                        .shareLiveWorkoutDetails
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "Live strength details",
                    norwegian: "Live styrkedata"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Shares current exercise, set, actual reps, weight, resistance, rest and rowing distance. Off by default.",
                    norwegian:
                        "Deler øvelse, sett, faktiske reps, vekt, motstand, pause og rodd distanse. Av som standard."
                ),
                icon: "dumbbell.fill",
                isOn:
                    $homeAssistant
                        .shareStrengthDetails
            )

            sharingToggle(
                title: ATHLTHLocalization.choose(
                    english: "PRs and milestones",
                    norwegian: "PR-er og milepæler"
                ),
                detail: ATHLTHLocalization.choose(
                    english:
                        "Lets Home Assistant react to personal records, achievements, completed goals and challenges. Off by default.",
                    norwegian:
                        "Lar Home Assistant reagere på personlige rekorder, achievements, fullførte mål og challenges. Av som standard."
                ),
                icon: "trophy.fill",
                isOn:
                    $homeAssistant
                        .shareMilestoneEvents
            )

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Turning a category off also clears its current value from the ATHLTH entities in Home Assistant.",
                    norwegian:
                        "Når du slår av en kategori, fjernes også den gjeldende verdien fra ATHLTH-entitetene i Home Assistant."
                )
            )
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func sharingToggle(
        title: String,
        detail: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private func clearDisabledValues() {
        guard homeAssistant.isConnected else {
            return
        }

        Task {
            await homeAssistant.clearDisabledValues()
        }
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Nearby Home Assistant",
                            norwegian: "Home Assistant i nærheten"
                        )
                    )
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "ATHLTH searches your local network automatically.",
                            norwegian:
                                "ATHLTH søker automatisk på lokalnettet ditt."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                if homeAssistant.connectionState == .discovering {
                    ProgressView()
                } else {
                    Button {
                        homeAssistant.startDiscovery()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Pairing code",
                        norwegian: "Paringskode"
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "In Home Assistant, open Settings → Devices & services → ATHLTH → Configure. Enter the 6-digit code shown there.",
                        norwegian:
                            "I Home Assistant åpner du Innstillinger → Enheter og tjenester → ATHLTH → Konfigurer. Skriv inn den 6-sifrede koden som vises der."
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

                TextField(
                    "000 000",
                    text: $pairingCode
                )
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .tracking(5)
                .onChange(of: pairingCode) { _, value in
                    let digits =
                        value.filter(\.isNumber)
                    pairingCode =
                        String(
                            digits.prefix(6)
                        )
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    ATHLTHTheme.canvasTop,
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }

            if homeAssistant.discoveredInstances.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Searching for _home-assistant._tcp on your network…",
                            norwegian:
                                "Søker etter _home-assistant._tcp på nettverket ditt…"
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            homeAssistant.discoveredInstances
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, instance in
                        Button {
                            homeAssistant.pairLocally(
                                to: instance,
                                pairingCode: pairingCode
                            )
                        } label: {
                            HStack(spacing: 13) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            Color(
                                                red: 0.12,
                                                green: 0.58,
                                                blue: 0.86
                                            )
                                            .opacity(0.11)
                                        )
                                        .frame(width: 42, height: 42)

                                    Image(systemName: "house.fill")
                                        .foregroundStyle(
                                            Color(
                                                red: 0.12,
                                                green: 0.58,
                                                blue: 0.86
                                            )
                                        )
                                }

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(instance.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )

                                    Text(instance.displayURL)
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                if let version = instance.version {
                                    Text(version)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText.opacity(0.7)
                                    )
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            pairingCode.filter(\.isNumber).count != 6 ||
                            homeAssistant.connectionState == .pairing
                        )

                        if index <
                            homeAssistant.discoveredInstances.count - 1 {
                            Divider()
                                .padding(.leading, 55)
                        }
                    }
                }
            }

            Label(
                ATHLTHLocalization.choose(
                    english:
                        "Code pairing stays on your local network. Home Assistant sign-in is kept only as a fallback.",
                    norwegian:
                        "Kodeparing skjer på lokalnettet. Home Assistant-innlogging beholdes kun som reserve."
                ),
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(18)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var manualConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Enter address manually",
                    norwegian: "Skriv inn adresse manuelt"
                )
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Use this only if your Home Assistant instance is not discovered automatically. The same 6-digit pairing code above is used.",
                    norwegian:
                        "Bruk dette kun dersom Home Assistant ikke blir funnet automatisk. Den samme 6-sifrede paringskoden over brukes."
                )
            )
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            TextField(
                "http://homeassistant.local:8123",
                text: $manualAddress
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                ATHLTHTheme.canvasTop,
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            Button {
                homeAssistant.pairLocallyManually(
                    address: manualAddress,
                    pairingCode: pairingCode
                )
            } label: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Pair with code",
                        norwegian: "Par med kode"
                    )
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                manualAddress.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty ||
                pairingCode.filter(\.isNumber).count != 6 ||
                homeAssistant.connectionState == .pairing
            )

            Button {
                homeAssistant.connectManually(
                    address: manualAddress
                )
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Use Home Assistant sign-in instead",
                        norwegian:
                            "Bruk Home Assistant-innlogging i stedet"
                    ),
                    systemImage:
                        "person.crop.circle.badge.checkmark"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .disabled(
                manualAddress.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty ||
                !homeAssistant.isOAuthClientConfigured
            )
        }
        .padding(18)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                ATHLTHLocalization.choose(
                    english: "How the connection works",
                    norwegian: "Slik fungerer tilkoblingen"
                ),
                systemImage: "lock.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Home Assistant generates a one-time 6-digit code that expires after five minutes. ATHLTH exchanges it locally for a random per-device signing secret stored in iOS Keychain. The code is never used again. OAuth sign-in remains available as a fallback.",
                    norwegian:
                        "Home Assistant genererer en 6-sifret engangskode som utløper etter fem minutter. ATHLTH bytter den lokalt mot en tilfeldig signeringsnøkkel for denne enheten som lagres i iOS Keychain. Koden brukes aldri igjen. OAuth-innlogging beholdes som reserve."
                )
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func connectionDetail(
        icon: String,
        title: String
    ) -> some View {
        Label {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }
}
