import Charts
import Combine
import SwiftUI

/// One private place for reusable athlete context and dated body measurements.
/// A changed reading does not silently overwrite Apple Health body mass.
struct ATHLTHPrivateProfileDetailsView: View {
    @EnvironmentObject private var session: AppSessionStore
    @StateObject private var checkInStore = RecoverySorenessStore()
    @State private var showingDailyCheckIn = false
    @State private var profile = ATHLTHTrainingProfile()
    @State private var selectedMetric: ATHLTHBodyMetric = .weight
    @State private var measureDate = Date()
    @State private var measureValue = ""
    @State private var errorText: String?
    @State private var showingMeasurementEditor = false
    @State private var profileLoadedFor: UUID?
    @State private var persistedProfile: ATHLTHTrainingProfile?
    @State private var visibleHistoryCount = 20
    @State private var savedNotice = false

    private func localized(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        let readings = profile.readings(for: selectedMetric)
        let latest = profile.latestByMetric()
        return LazyVStack(alignment: .leading, spacing: 19) {
            checkInCard
            ATHLTHInjuryRestrictionsEditor(restrictions: Binding(
                get: { profile.injuryRestrictions ?? [] },
                set: { updated in
                    profile.injuryRestrictions = updated
                    profile.updatedAt = .now
                    persist()
                }
            ))
            metricsCard(latest: latest)
            if !readings.isEmpty {
                trendCard(readings: readings)
                historyCard(readings: readings)
            }
            notesCard
            Text(localized(
                "Manual body measurements synchronize privately between your signed-in devices. Personal notes and injury restrictions remain on this device. None of this appears on your public profile or is automatically shared with Coach or Apple Health.",
                "Kroppsmål du registrerer selv synkroniseres privat mellom innloggede enheter. Personlige notater og skadebegrensninger beholdes på denne enheten. Ingenting vises på din offentlige profil eller deles automatisk med Coach eller Apple Helse."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .onAppear {
            loadProfile()
            checkInStore.reloadFromStorage()
        }
        .onChange(of: session.profile.userID) { _, _ in
            loadProfile()
            checkInStore.reloadFromStorage()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.dailyCheckInDidUpdate")
        )) { _ in
            checkInStore.reloadFromStorage()
        }
        .sheet(isPresented: $showingMeasurementEditor) {
            measurementEditor
        }
        .sheet(isPresented: $showingDailyCheckIn) {
            RecoverySorenessLogView(store: checkInStore)
        }
        .onChange(of: selectedMetric) { _, _ in
            visibleHistoryCount = 20
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthTrainingDataDidChange
        ).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            reloadProfileIfChanged()
            checkInStore.reloadFromStorage()
        }
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("Daily check-in", "Daglig innsjekk"),
                      systemImage: "heart.text.clipboard")
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Label(
                    checkInStore.hasTodayCheckIn
                        ? localized("Completed today", "Registrert i dag")
                        : localized("Not recorded", "Ikke registrert"),
                    systemImage: checkInStore.hasTodayCheckIn
                        ? "checkmark.circle.fill" : "circle.dashed"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(checkInStore.hasTodayCheckIn
                    ? ATHLTHPlanDesign.accentInk
                    : ATHLTHPlanDesign.secondaryInk)
            }
            Text(localized(
                "How do you feel? Track energy, stress, soreness and motivation without changing your watch measurements.",
                "Hvordan har du det? Følg energi, stress, ømhet og motivasjon – uavhengig av målingene fra klokken."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            if checkInStore.hasTodayCheckIn {
                HStack(spacing: 8) {
                    checkInMetric(localized("Energy", "Energi"), checkInStore.todayEnergy)
                    checkInMetric(localized("Stress", "Stress"), checkInStore.todayStress)
                    checkInMetric(localized("Soreness", "Ømhet"), checkInStore.todayOverallSoreness)
                    checkInMetric(localized("Motivation", "Motivasjon"), checkInStore.todayMotivation)
                }
            }

            let week = checkInStore.entries.filter {
                $0.date >= Calendar.current.startOfDay(
                    for: Calendar.current.date(byAdding: .day, value: -6,
                                               to: Date()) ?? Date()
                ) && $0.date <= Date()
            }
            if !week.isEmpty {
                Text(localized("Check-ins last 7 days", "Innsjekker siste 7 dager") +
                     " · \(week.count)/7")
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            Button {
                showingDailyCheckIn = true
            } label: {
                Label(
                    checkInStore.hasTodayCheckIn
                        ? localized("Update today's check-in", "Oppdater dagens innsjekk")
                        : localized("Check in", "Registrer innsjekk"),
                    systemImage: "square.and.pencil"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHPlanDesign.accentInk)
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
    }

    private func checkInMetric(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 5) {
            Text(value.map { "\($0)/5" } ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(localized("Training preferences", "Treningspreferanser"),
                  systemImage: "figure.strengthtraining.traditional")
                .font(.headline)
            Text(localized(
                "Your experience, preferred activities, equipment and training conditions. This is your personal note.",
                "Din erfaring, treningsformer, utstyr og treningsforutsetninger. Dette er dine egne notater."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            TextField(
                localized("Training preferences", "Treningspreferanser"),
                text: $profile.trainingNotes, axis: .vertical
            )
            .lineLimit(3...6)
            .padding(8)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))

            Text(localized(
                "Additional training considerations (optional)",
                "Andre treningshensyn (valgfritt)"
            ))
            .font(.subheadline.weight(.semibold))
            Text(localized(
                "Existing notes are kept. Use the structured injury list above for each affected area.",
                "Tidligere notater beholdes. Bruk skadeoversikten over for hvert berørte område."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            TextField(
                localized("Other notes", "Andre notater"),
                text: $profile.injuryAndLimitations, axis: .vertical
            )
            .lineLimit(2...4)
            .padding(8)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 13))
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))

            Button {
                profile.trainingNotes = String(profile.trainingNotes.prefix(1_500))
                profile.injuryAndLimitations =
                    String(profile.injuryAndLimitations.prefix(1_500))
                profile.updatedAt = .now
                persist()
                savedNotice = true
            } label: {
                Label(localized("Save training details", "Lagre treningsopplysninger"),
                      systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHPlanDesign.accentInk)
            if savedNotice {
                Label(localized("Saved privately", "Lagret privat"),
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
    }

    private func metricsCard(latest: [ATHLTHBodyMetric: ATHLTHBodyMeasurement]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(localized("Body measurements", "Kroppsmål"))
                    .font(.headline)
                Spacer()
                Button {
                    measureDate = Date()
                    measureValue = profile.latest(selectedMetric).map {
                        String(format: "%.1f", $0.value)
                    } ?? ""
                    errorText = nil
                    showingMeasurementEditor = true
                } label: {
                    Label(localized("Add reading", "Legg til"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .tint(ATHLTHPlanDesign.accentInk)
            }
            Text(localized(
                "Track weight and circumference. All values are optional and you decide what to measure.",
                "Følg vekt og omkrets. Alle mål er valgfrie, og du velger selv hva du registrerer."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                ForEach(ATHLTHBodyMetric.allCases) { metric in
                    Button {
                        selectedMetric = metric
                        savedNotice = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(metric.name).font(.caption.weight(.medium))
                            if let latest = latest[metric] {
                                Text(String(format: "%.1f %@", latest.value, metric.unit))
                                    .font(.subheadline.weight(.bold))
                            } else {
                                Text("—").font(.subheadline.weight(.semibold))
                            }
                        }
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .padding(11)
                        .background(
                            selectedMetric == metric
                                ? ATHLTHPlanDesign.selectedSurface : Color.white,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    ATHLTHPlanDesign.accentInk.opacity(
                                        selectedMetric == metric ? 0.5 : 0.10
                                    ), lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
    }

    private func trendCard(readings: [ATHLTHBodyMeasurement]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Progress", "Utvikling") + " · " + selectedMetric.name)
                .font(.headline)
            if readings.count > 1,
               let first = readings.first, let last = readings.last {
                Text(String(format: "%+.1f %@",
                            last.value - first.value, selectedMetric.unit))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(localized("From first to latest reading", "Fra første til siste måling"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if readings.count > 1 {
                Chart(readings) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.unit, point.value)
                    )
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.unit, point.value)
                    )
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                .frame(height: 165)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .accessibilityLabel(localized(
                    "Body measurement progress", "Utvikling i kroppsmål"
                ))
            } else {
                Text(localized(
                    "Add another dated measurement to see the trend.",
                    "Legg til en ny datert måling for å se utviklingen."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
    }

    private func historyCard(readings: [ATHLTHBodyMeasurement]) -> some View {
        let visible = Array(readings.reversed().prefix(visibleHistoryCount))
        return LazyVStack(alignment: .leading, spacing: 10) {
            Text(localized("Measurement history", "Målehistorikk"))
                .font(.headline)
            ForEach(visible) { reading in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: "%.1f %@", reading.value, selectedMetric.unit))
                            .font(.subheadline.weight(.semibold))
                        Text(reading.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer()
                    Button {
                        measureDate = reading.date
                        measureValue = String(format: "%.1f", reading.value)
                        showingMeasurementEditor = true
                    } label: {
                        Image(systemName: "pencil").font(.caption)
                    }
                    .accessibilityLabel(localized("Edit reading", "Endre måling"))
                    Button(role: .destructive) {
                        profile.measurements.removeAll { $0.id == reading.id }
                        persist()
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .accessibilityLabel(localized("Delete reading", "Slett måling"))
                }
                .padding(.vertical, 5)
                if reading.id != visible.last?.id {
                    Divider().opacity(0.5)
                }
            }
            if visible.count < readings.count {
                Button {
                    visibleHistoryCount += 20
                } label: {
                    Label(localized("Show more", "Vis flere") + " (\(readings.count - visible.count))",
                          systemImage: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
    }

    private var measurementEditor: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(localized("Measurement", "Måling"),
                           selection: $selectedMetric) {
                        ForEach(ATHLTHBodyMetric.allCases) { metric in
                            Text(metric.name).tag(metric)
                        }
                    }
                    DatePicker(localized("Date", "Dato"), selection: $measureDate,
                               in: ...Date(), displayedComponents: .date)
                    TextField(selectedMetric.unit, text: $measureValue)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text(localized(
                        "Measure consistently at approximately the same point on your body. Only one reading of each type per day is kept.",
                        "Mål på samme sted hver gang. Det lagres én måling per type per dag."
                    ))
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle(localized("Record measurement", "Registrer måling"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel", "Avbryt")) {
                        showingMeasurementEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Save", "Lagre")) {
                        let cleaned = measureValue.replacingOccurrences(of: ",", with: ".")
                        guard let value = Double(cleaned),
                              profile.record(metric: selectedMetric, value: value,
                                             at: measureDate) else {
                            errorText = localized("Check the measurement value.",
                                                  "Kontroller måleverdien.")
                            return
                        }
                        persist()
                        showingMeasurementEditor = false
                    }
                }
            }
        }
    }

    private func loadProfile() {
        let id = session.profile.userID
        guard profileLoadedFor != id else {
            reloadProfileIfChanged()
            return
        }
        let loaded = ATHLTHTrainingProfile.load(userID: id)
        profile = loaded
        persistedProfile = loaded
        profileLoadedFor = id
        visibleHistoryCount = 20
    }

    private func reloadProfileIfChanged() {
        let id = session.profile.userID
        guard profileLoadedFor == id, let previous = persistedProfile else {
            loadProfile()
            return
        }
        let incoming = ATHLTHTrainingProfile.load(userID: id)
        guard incoming != previous else { return }
        // An unrelated workout/sync notification must not erase notes
        // that the athlete is still editing.
        var merged = incoming
        if profile.trainingNotes != previous.trainingNotes {
            merged.trainingNotes = profile.trainingNotes
        }
        if profile.injuryAndLimitations != previous.injuryAndLimitations {
            merged.injuryAndLimitations = profile.injuryAndLimitations
        }
        persistedProfile = incoming
        if merged != profile { profile = merged }
    }

    private func persist() {
        profile.save(userID: session.profile.userID)
        persistedProfile = profile
        NotificationCenter.default.post(name: .athlthTrainingDataDidChange, object: nil)
    }
}
