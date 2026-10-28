import Charts
import SwiftUI

/// One private place for reusable athlete context and dated body measurements.
/// A changed reading does not silently overwrite Apple Health body mass.
struct ATHLTHTrainingProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @StateObject private var checkInStore = RecoverySorenessStore()
    @State private var showingDailyCheckIn = false
    @State private var showingGoalCreation = false
    @State private var profile = ATHLTHTrainingProfile()
    @State private var selectedMetric: ATHLTHBodyMetric = .weight
    @State private var measureDate = Date()
    @State private var measureValue = ""
    @State private var errorText: String?
    @State private var showingMeasurementEditor = false
    @State private var profileLoadedFor: UUID?
    @State private var savedNotice = false

    private func localized(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                intro
                goalsCard
                checkInCard
                metricsCard
                if !profile.readings(for: selectedMetric).isEmpty {
                    trendCard
                    historyCard
                }
                notesCard
                Text(localized(
                    "Private to this account on this device. Body measurements are not automatically shared with Coach, Apple Health or your public profile. If you reinstall the app, locally stored readings may be lost until cloud backup is supported.",
                    "Privat for denne kontoen på denne enheten. Kroppsmål sendes ikke automatisk til Coach, Apple Helse eller din offentlige profil. Ved reinstallasjon kan lokale målinger gå tapt til sikkerhetskopiering i skyen er støttet."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(16)
            .padding(.bottom, 45)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .navigationTitle(localized("Training profile", "Treningsprofil"))
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showingGoalCreation) {
            GoalCreationView()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthTrainingDataDidChange
        )) { _ in
            profile = ATHLTHTrainingProfile.load(userID: session.profile.userID)
            checkInStore.reloadFromStorage()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(localized("MY TRAINING PROFILE", "MIN TRENINGSPROFIL"),
                  systemImage: "person.crop.rectangle.stack")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(localized("Your training, in one place.",
                           "Din trening. Samlet på ett sted."))
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(localized(
                "Keep your goals, daily check-ins and body measurements together. Your training profile is private and independent of Coach.",
                "Samle målsetninger, daglig innsjekk og kroppsmål. Treningsprofilen er privat og fungerer uavhengig av Coach."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }

    private var activeGoals: [ATHLTHGoal] {
        goalStore.goals.filter { $0.status == .active }
    }

    private func goalProgress(_ goal: ATHLTHGoal) -> Double {
        if goal.bodyMeasurementGoal != nil {
            return min(max(ATHLTHBodyGoalCheckInPolicy.progress(goal, profile: profile), 0), 1)
        }
        return min(max(goal.progress, 0), 1)
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(localized("My goals", "Mine mål"), systemImage: "target")
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Text("\(activeGoals.count) " +
                     localized("active", "aktive"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }

            if let primary = goalStore.primaryGoal {
                NavigationLink {
                    GoalDetailView(goalID: primary.id)
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(localized("MAIN GOAL", "HOVEDMÅL"), systemImage: "star.fill")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        HStack(alignment: .center, spacing: 9) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(primary.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .lineLimit(2)
                                Text(primary.deadline.map {
                                    localized("Target ", "Måldato ") +
                                        $0.formatted(date: .abbreviated, time: .omitted)
                                } ?? localized("No deadline", "Ingen måldato"))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer()
                            Text("\(Int((goalProgress(primary) * 100).rounded()))%")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        ProgressView(value: goalProgress(primary))
                            .tint(ATHLTHPlanDesign.accentInk)
                    }
                    .padding(13)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            } else {
                Text(goalStore.goals.isEmpty
                     ? localized(
                        "Set a goal for your training. You can track progress and milestones here.",
                        "Sett deg et treningsmål. Her kan du følge fremgang og delmål."
                     )
                     : localized(
                        "No active main goal. Manage your goals or choose a new priority.",
                        "Du har ikke et aktivt hovedmål. Administrer målene eller velg en ny prioritet."
                     ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            HStack(spacing: 9) {
                NavigationLink {
                    GoalsHubView()
                } label: {
                    Label(localized("View all goals", "Se alle mål"),
                          systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    showingGoalCreation = true
                } label: {
                    Label(localized("New goal", "Nytt mål"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.accentInk)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .athlthPlanCard(radius: 19)
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
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.vertical, 8)
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
            TextEditor(text: $profile.trainingNotes)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))

            Label(localized("Injuries and limitations", "Skader og begrensninger"),
                  systemImage: "cross.case")
                .font(.headline)
            Text(localized(
                "Describe movements to avoid, current limitations, pain or medical guidance you want to remember. Never shared automatically.",
                "Beskriv bevegelser du må unngå, utfordringer, smerter eller andre hensyn du ønsker å huske. Deles aldri automatisk."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            TextEditor(text: $profile.injuryAndLimitations)
                .frame(minHeight: 95)
                .scrollContentBackground(.hidden)
                .padding(8)
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
                Label(localized("Save training profile", "Lagre treningsprofil"),
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

    private var metricsCard: some View {
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
                            if let latest = profile.latest(metric) {
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

    private var trendCard: some View {
        let readings = profile.readings(for: selectedMetric)
        return VStack(alignment: .leading, spacing: 12) {
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

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Measurement history", "Målehistorikk"))
                .font(.headline)
            ForEach(profile.readings(for: selectedMetric).reversed()) { reading in
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
                if reading.id != profile.readings(for: selectedMetric).first?.id {
                    Divider().opacity(0.5)
                }
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
        guard profileLoadedFor != id else { return }
        profile = ATHLTHTrainingProfile.load(userID: id)
        profileLoadedFor = id
    }

    private func persist() {
        profile.save(userID: session.profile.userID)
        NotificationCenter.default.post(name: .athlthTrainingDataDidChange, object: nil)
    }
}
