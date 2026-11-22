import SwiftUI

/// The same competition discipline is available for group competitions.
/// Capturing GPS, countdown and equipment evidence is delegated to the
/// universal workout engine, not simulated by this configuration screen.
struct ATHLTHCompetitionRaceRulesSection: View {
    @Binding var settings: ATHLTHTournamentCompetitionSettings
    let activities: Set<ATHLTHTournamentActivity>
    @State private var showingSavedRoutes = false
    @State private var showingLapPoint = false

    private var runningAllowed: Bool { activities.contains(.running) }
    private var race: Binding<ATHLTHCompetitionRaceRules> {
        $settings.race
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Konkurranseøvelse")
                .font(.system(size: 23, design: .serif))
                .foregroundStyle(ATHLTHArenaV3Style.ink)
            Text("Velg hva deltakerne faktisk skal gjennomføre. Dette er ikke en ekstra treningsmotor.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)

            Picker("Hva konkurrerer dere i?", selection: race.discipline) {
                ForEach(ATHLTHCompetitionDiscipline.allCases.filter {
                    $0 != .sprint || runningAllowed
                }) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.menu)

            if settings.race.discipline == .sprint {
                Picker("Sprintform", selection: race.sprintMode) {
                    ForEach(ATHLTHCompetitionSprintMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Picker("Sprintmål", selection: race.sprintTarget) {
                    ForEach(ATHLTHCompetitionSprintTarget.allCases) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                .pickerStyle(.segmented)
            }

            if settings.race.discipline == .sprint ||
               settings.race.discipline == .distance {
                if settings.race.discipline == .distance ||
                   settings.race.sprintTarget == .distance {
                    Stepper(
                        "Mål: \(settings.race.targetDistanceMeters) meter",
                        value: race.targetDistanceMeters, in: 100...100_000,
                        step: settings.race.targetDistanceMeters < 1000 ? 50 : 500
                    )
                    .font(.subheadline)
                }
            }

            if settings.race.discipline == .duration ||
               (settings.race.discipline == .sprint &&
                settings.race.sprintTarget == .duration) {
                Stepper("Tid: \(settings.race.targetDurationSeconds) sekunder",
                        value: race.targetDurationSeconds, in: 10...86_400,
                        step: settings.race.targetDurationSeconds < 180 ? 10 : 60)
                    .font(.subheadline)
            }

            if settings.race.discipline == .sprint &&
               settings.race.sprintTarget == .route {
                Button {
                    showingSavedRoutes = true
                } label: {
                    Label(settings.race.routeName.isEmpty
                          ? "Velg lagret rute"
                          : settings.race.routeName,
                          systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                }
                if settings.race.routeID == nil {
                    Text("Alle må bruke samme lagrede rute.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if settings.race.discipline == .laps {
                Stepper("Antall runder: \(settings.race.lapCount)",
                        value: race.lapCount, in: 1...500)
                    .font(.subheadline)
                TextField("Beskriv felles løype, f.eks. rundt bygget",
                          text: race.lapCourseName, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                Picker("Hvordan telles runder?", selection: race.lapVerification) {
                    ForEach(ATHLTHCompetitionLapVerification.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                if settings.race.lapVerification == .gps {
                    Button {
                        showingLapPoint = true
                    } label: {
                        Label(settings.race.lapCourseLatitude == nil
                              ? "Velg felles rundepassasje på kart"
                              : "Felles rundepassasje er valgt",
                              systemImage: "mappin.and.ellipse")
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    }
                    Text("GPS-passering må bekreftes av øktmotoren med riktig retning og nøyaktighet. En kartpinne alene teller ikke en runde.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                } else {
                    Text("Runder godkjennes av arrangøren. Kjent distanse er ikke nødvendig, men alle skal følge samme løype.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
            }

            if settings.race.discipline == .sprint {
                Stepper("Nedtelling før start: \(settings.race.countdownSeconds) sek",
                        value: race.countdownSeconds, in: 5...30, step: 5)
                    .font(.subheadline)
                Label("Et gyldig starttidspunkt må komme fra konkurransen. Start før startsignalet skal ikke gi et gyldig resultat.",
                      systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            Divider()

            Text("Påkrevd registreringsenhet")
                .font(.subheadline.weight(.semibold))
            Picker("Registreringsenhet", selection: race.recordingDevice) {
                ForEach(ATHLTHCompetitionRecordingDevice.allCases) { device in
                    Text(device.title).tag(device)
                }
            }
            .pickerStyle(.menu)
            if settings.race.recordingDevice == .appleWatch {
                Label("Resultater må komme fra en dokumentert Apple Watch-økt. Enhetens opprinnelse skal kontrolleres før resultatet godkjennes.",
                      systemImage: "applewatch")
                    .font(.caption)
                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
            }

            TextField("Tillatt/påkrevd utstyr (valgfritt)",
                      text: race.equipmentRules, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))

            Toggle("Tillat frivillig deling av liveposisjon",
                   isOn: race.allowOptInLiveLocation)
                .tint(ATHLTHArenaV3Style.gold)
                .font(.subheadline)
            Text("Ingen posisjon deles automatisk. Hver deltaker må selv aktivere deling og gi stedstillatelse; delingen avsluttes når økten avsluttes.")
                .font(.caption)
                .foregroundStyle(ATHLTHArenaV3Style.secondary)
        }
        .padding(15)
        .background(ATHLTHArenaV3Style.panel())
        .sheet(isPresented: $showingSavedRoutes) {
            NavigationStack {
                SavedRoutesView(selectionTitle: "Konkurranserute") { route in
                    settings.race.routeID = route.id
                    settings.race.routeName = String(route.title.prefix(120))
                    showingSavedRoutes = false
                }
            }
        }
        .sheet(isPresented: $showingLapPoint, onDismiss: {
            settings.race.lapCourseLatitude = settings.meetingLat
            settings.race.lapCourseLongitude = settings.meetingLon
        }) {
            ATHLTHCompetitionMeetingPointPicker(settings: $settings)
        }
        .onChange(of: activities) { _, current in
            if !current.contains(.running) &&
               settings.race.discipline == .sprint {
                settings.race.discipline = .workout
            }
        }
    }
}
