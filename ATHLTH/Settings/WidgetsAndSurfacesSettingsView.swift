import SwiftUI

struct ATHLTHWidgetsAndSurfacesSettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore

    @State private var liveConfiguration =
        ATHLTHLiveWorkoutPreferencesStore.load()

    private var settingsColumns: [GridItem] {
        [GridItem(.adaptive(
            minimum: horizontalSizeClass == .regular ? 410 : 270
        ), spacing: 18)]
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro

                LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                    liveWorkoutSettings
                    ATHLTHCard {
                        watchPersonalizationSettings
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Widgets and other surfaces", "Widgeter og andre flater"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(tr(
                        "These are visual examples. Live information comes from your devices.",
                        "Dette er illustrasjoner. Reelle data hentes fra enhetene dine."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }

                LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 18) {
                    ForEach(ATHLTHExternalSurface.allCases) { surface in
                        surfaceCard(surface)
                    }
                }

                availabilityNote
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(tr("Widgets & Surfaces", "Widgeter og flater"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            liveConfiguration = ATHLTHLiveWorkoutPreferencesStore.load()
        }
        .onChange(of: liveConfiguration) { _, configuration in
            ATHLTHLiveWorkoutPreferencesStore.save(configuration)
            watchConnection.sendLiveSurfaceConfiguration(configuration)
        }
    }

    private var liveWorkoutSettings: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 42, height: 42)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Live workout display", "Live-visning av økt"))
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(
                            tr("Choose what ATHLTH shows during an active workout. Smart priority highlights the most relevant information.", "Velg hva ATHLTH skal vise under økten. Smart prioritet fremhever den viktigste informasjonen.")
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                Toggle(
                    tr("Dynamic Island & Live Activity", "Dynamic Island og Live Activity"),
                    isOn: $liveConfiguration.dynamicIslandEnabled
                )

                Toggle(
                    tr("Apple Watch Live Info", "Live-info på Apple Watch"),
                    isOn: $liveConfiguration.watchEnabled
                )

                Toggle(
                    tr("Smart Priority", "Smart prioritet"),
                    isOn: $liveConfiguration.smartPriorityEnabled
                )

                Toggle(
                    tr("Guidance haptics", "Haptiske veiledningsvarsler"),
                    isOn: $liveConfiguration.hapticsEnabled
                )

                Toggle(
                    tr("Guidance voice alerts", "Talevarsler for veiledning"),
                    isOn: $liveConfiguration.audioAlertsEnabled
                )

                Text(
                    tr("These master controls also apply in Workout Guidance. They affect Route Guardian, goal and Ghost alerts on iPhone and Apple Watch. Audio Coach is configured separately.", "Dette er de samme hovedvalgene som under Øktveiledning. De påvirker Route Guardian-, mål- og Ghost-varsler på iPhone og Apple Watch. Audio Coach styres separat.")
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Divider()

                ForEach(ATHLTHLiveWorkoutFeature.allCases) { feature in
                    Toggle(
                        isOn: featureBinding(feature)
                    ) {
                        Label(
                            feature.title,
                            systemImage: feature.systemImage
                        )
                    }

                    Text(feature.subtitle)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .padding(.leading, 28)

                    if feature != ATHLTHLiveWorkoutFeature.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private var watchPersonalizationSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Apple Watch display",
                    norwegian: "Apple Watch-visning"
                ),
                systemImage: "applewatch"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Choose the main metric and the first page of your run. Automatic keeps the current run/walk defaults.",
                norwegian: "Velg hovedmåling og startsiden for løping. Automatisk beholder dagens standardvalg for løping og gåtur."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)

            Picker(
                ATHLTHLocalization.choose(
                    english: "Primary running metric",
                    norwegian: "Hovedmåling"
                ),
                selection: Binding(
                    get: { liveConfiguration.preferredRunMetricRaw ?? "automatic" },
                    set: { liveConfiguration.preferredRunMetricRaw = $0 }
                )
            ) {
                Text(ATHLTHLocalization.choose(
                    english: "Automatic", norwegian: "Automatisk"
                )).tag("automatic")
                Text(ATHLTHLocalization.choose(
                    english: "Pace", norwegian: "Tempo"
                )).tag("pace")
                Text(ATHLTHLocalization.choose(
                    english: "Distance", norwegian: "Distanse"
                )).tag("distance")
            }
            .pickerStyle(.menu)

            Picker(
                ATHLTHLocalization.choose(
                    english: "Run start page", norwegian: "Startside for løping"
                ),
                selection: Binding(
                    get: { liveConfiguration.preferredRunPageRaw ?? "metrics" },
                    set: { liveConfiguration.preferredRunPageRaw = $0 }
                )
            ) {
                Text(ATHLTHLocalization.choose(
                    english: "Live metrics", norwegian: "Live målinger"
                )).tag("metrics")
                Text(ATHLTHLocalization.choose(
                    english: "Heart rate", norwegian: "Puls"
                )).tag("pulse")
                Text("Audio Coach").tag("coach")
            }
            .pickerStyle(.menu)

            Toggle(
                ATHLTHLocalization.choose(
                    english: "High contrast on Watch",
                    norwegian: "Høy kontrast på klokken"
                ),
                isOn: Binding(
                    get: { liveConfiguration.strongWatchContrast == true },
                    set: { liveConfiguration.strongWatchContrast = $0 }
                )
            )

            Toggle(
                ATHLTHLocalization.choose(
                    english: "Private Always-On screen",
                    norwegian: "Privat Always-On-skjerm"
                ),
                isOn: Binding(
                    get: { liveConfiguration.privateAlwaysOn == true },
                    set: { liveConfiguration.privateAlwaysOn = $0 }
                )
            )

            Text(ATHLTHLocalization.choose(
                english: "Privacy mode shows only activity type and elapsed time while your wrist is down. Detailed workout data is still available when the Watch wakes. Changes sync to the Watch when connected.",
                norwegian: "Personvernmodus viser bare treningsform og økttid når håndleddet er senket. Detaljene vises igjen når klokken vekkes. Valgene synkroniseres når klokken er tilkoblet."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureBinding(
        _ feature: ATHLTHLiveWorkoutFeature
    ) -> Binding<Bool> {
        Binding(
            get: {
                liveConfiguration.isEnabled(feature)
            },
            set: { enabled in
                liveConfiguration.setEnabled(
                    enabled,
                    for: feature
                )
            }
        )
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("ATHLTH EVERYWHERE", "ATHLTH OVERALT"))
                .font(.caption2.weight(.bold))
                .tracking(2.1)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

            Text(tr("Widgets & Surfaces", "Widgeter og flater"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                tr("Control how ATHLTH appears outside the app: on the Home Screen, during workouts, through Siri and on the Lock Screen.", "Her bestemmer du hvordan ATHLTH vises utenfor appen – på Hjem-skjermen, under økter, via Siri og på låseskjermen.")
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func surfaceCard(
        _ surface: ATHLTHExternalSurface
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: surface.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(surface.tint)
                        .frame(width: 46, height: 46)
                        .background(
                            surface.tint.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(surface.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(surface.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(surface.statusTitle)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: Capsule()
                        )
                }

                preview(for: surface)
            }
        }
    }

    @ViewBuilder
    private func preview(
        for surface: ATHLTHExternalSurface
    ) -> some View {
        switch surface {
        case .homeScreen:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(tr("Recovery", "Restitusjon"), systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text("82")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text(tr("Good", "God"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                ProgressView(value: 0.82)
                    .tint(ATHLTHPlanDesign.accentInk)
                    .frame(maxWidth: 130)
            }
            .padding(14)
            .background(
                ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

        case .liveActivity:
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Outdoor run", "Utendørsløping"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                    Text("32:18")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("5.2 km")
                    Text("5:56 /km")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .background(
                Color.black,
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )

        case .siriShortcuts:
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: Circle()
                    )

                Text(tr("“What’s my recovery today?”", "«Hvordan er formen min i dag?»"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer()
            }
            .padding(14)
            .background(
                ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

        case .lockScreen:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("9:41")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(tr("Recovery 82", "Restitusjon 82"))
                        .font(.caption.weight(.semibold))
                }

                Divider()
                    .frame(height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Label(tr("In progress", "Pågående økt"), systemImage: "figure.run")
                        .font(.caption)
                    Text("32:18")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                }

                Spacer()
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentDeep,
                        ATHLTHPlanDesign.accentInk
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
    }

    private var availabilityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ATHLTHTheme.accentDeep)

            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Available in iOS", "Tilgjengelig i iOS"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    tr("Add ATHLTH using the Home Screen or Lock Screen widget gallery. Supported workouts can show a Live Activity when iOS permissions allow it. Siri and Shortcuts provide ATHLTH actions.", "Legg til ATHLTH fra widgetgalleriet på Hjem-skjermen eller låseskjermen. Støttede treningsøkter kan vise Live Activity når iOS-tillatelser er aktivert. ATHLTH-handlinger er tilgjengelige i Siri og Snarveier.")
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.champagneSoft,
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }
}

private enum ATHLTHExternalSurface: String, CaseIterable, Identifiable {
    case homeScreen
    case liveActivity
    case siriShortcuts
    case lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homeScreen:
            return ATHLTHLocalization.choose(english: "Home Screen widget", norwegian: "Hjem-skjermwidget")
        case .liveActivity:
            return "Live Activity"
        case .siriShortcuts:
            return ATHLTHLocalization.choose(english: "Siri & Shortcuts", norwegian: "Siri og Snarveier")
        case .lockScreen:
            return ATHLTHLocalization.choose(english: "Lock Screen", norwegian: "Låseskjerm")
        }
    }

    var statusTitle: String {
        switch self {
        case .homeScreen, .lockScreen:
            return ATHLTHLocalization.choose(english: "Ready", norwegian: "Klar")
        case .liveActivity:
            return ATHLTHLocalization.choose(english: "Automatic", norwegian: "Automatisk")
        case .siriShortcuts:
            return ATHLTHLocalization.choose(english: "Available", norwegian: "Tilgjengelig")
        }
    }

    var subtitle: String {
        switch self {
        case .homeScreen:
            return ATHLTHLocalization.choose(english: "Recovery, your next session and key insights at a glance.", norwegian: "Restitusjon, neste økt og viktige treningssignaler i én oversikt.")
        case .liveActivity:
            return ATHLTHLocalization.choose(english: "Follow an active workout from the Lock Screen and Dynamic Island.", norwegian: "Følg økten direkte fra låseskjermen og Dynamic Island.")
        case .siriShortcuts:
            return ATHLTHLocalization.choose(english: "Ask Siri about recovery, upcoming workouts and goals.", norwegian: "Bruk Siri og Snarveier til å spørre om restitusjon, økter og mål.")
        case .lockScreen:
            return ATHLTHLocalization.choose(english: "See recovery, your next session and live activity without opening the app.", norwegian: "Se restitusjon, neste økt og pågående aktivitet uten å åpne appen.")
        }
    }

    var systemImage: String {
        switch self {
        case .homeScreen:
            return "rectangle.grid.2x2"
        case .liveActivity:
            return "dot.radiowaves.left.and.right"
        case .siriShortcuts:
            return "waveform"
        case .lockScreen:
            return "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .homeScreen:
            return ATHLTHPlanDesign.accentInk
        case .liveActivity:
            return ATHLTHTheme.accentDeep
        case .siriShortcuts:
            return ATHLTHPlanDesign.accentInk
        case .lockScreen:
            return ATHLTHTheme.primaryText
        }
    }
}
