import SwiftUI

/// The same competition discipline is available for group competitions.
/// Capturing GPS, countdown and equipment evidence is delegated to the
/// universal workout engine, not simulated by this configuration screen.
struct ATHLTHCompetitionRaceRulesSection: View {
    @Binding var settings: ATHLTHTournamentCompetitionSettings
    let activities: Set<ATHLTHTournamentActivity>
    var workoutOnly = false
    @State private var showingSavedRoutes = false
    @State private var showingLapPoint = false

    private var runningAllowed: Bool { activities.contains(.running) }
    private func disciplineTile(_ value: ATHLTHCompetitionDiscipline) -> some View {
        let selected = settings.race.discipline == value
        let symbol: String = {
            switch value {
            case .sprint: return "bolt"
            case .workout: return "figure.strengthtraining.traditional"
            case .distance: return "point.topleft.down.curvedto.point.bottomright.up"
            case .duration: return "timer"
            case .laps: return "arrow.clockwise"
            }
        }()
        return Button {
            settings.race.discipline = value
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: symbol).font(.title3)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                }
                .foregroundStyle(ATHLTHArenaV3Style.gold)
                Text(value.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(selected ? ATHLTHPlanDesign.selectedSurface : Color.white,
                        in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(ATHLTHArenaV3Style.gold.opacity(selected ? 0.65 : 0.12))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var race: Binding<ATHLTHCompetitionRaceRules> {
        $settings.race
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if workoutOnly {
                Text("Registrering og utstyr")
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
            } else {
            HStack(spacing: 12) {
                Image(systemName: "trophy")
                    .font(.title2)
                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                    .frame(width: 46, height: 46)
                    .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("KONKURRANSEØVELSE")
                        .font(.caption2.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text("Hva konkurrerer dere i?")
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 8)], spacing: 8) {
                ForEach(ATHLTHCompetitionDiscipline.allCases.filter {
                    workoutOnly ? $0 == .workout : ($0 != .sprint || runningAllowed)
                }) { value in
                    disciplineTile(value)
                }
            }

            }
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
                        "\(settings.race.targetDistanceMeters.formatted()) m",
                        value: race.targetDistanceMeters, in: 100...100_000,
                        step: settings.race.targetDistanceMeters < 1000 ? 50 : 500
                    )
                    .font(.headline.monospacedDigit())
                    .padding(14)
                    .background(ATHLTHPlanDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 14))
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
        .fullScreenCover(isPresented: $showingSavedRoutes) {
            NavigationStack {
                SavedRoutesView(selectionTitle: "Konkurranserute") { route in
                    settings.race.routeID = route.id
                    settings.race.routeName = String(route.title.prefix(120))
                    showingSavedRoutes = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Lukk") { showingSavedRoutes = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingLapPoint, onDismiss: {
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
