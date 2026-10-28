import Charts
import SwiftUI

/// A short, dedicated path for measurement goals. It reuses Training Profile
/// measurements rather than inventing another progress database.
struct ATHLTHBodyGoalCreationView: View {
    var onCreated: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore

    @State private var metric: ATHLTHBodyMetric = .waist
    @State private var baselineText = ""
    @State private var targetText = ""
    @State private var deadline = Calendar.current.date(
        byAdding: .month, value: 3, to: .now
    ) ?? .now
    @State private var interval = 14
    @State private var enableNotifications = true
    @State private var errorMessage: String?

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func number(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "."))
    }

    private var suggestedTitle: String {
        let current = number(baselineText)
        let target = number(targetText)
        let reduce = current != nil && target != nil && target! < current!
        let increase = current != nil && target != nil && target! > current!
        switch metric {
        case .waist:
            if reduce { return tr("Reduce waist measurement", "Reduser midjemålet") }
            if increase { return tr("Increase waist measurement", "Øk midjemålet") }
            return tr("Set a waist goal", "Sett mål for midjemålet")
        case .upperArm:
            if increase { return tr("Increase upper-arm measurement", "Øk overarmmålet") }
            if reduce { return tr("Reduce upper-arm measurement", "Reduser overarmmålet") }
            return tr("Set an upper-arm goal", "Sett mål for overarmmålet")
        case .weight:
            return tr("Reach my target weight", "Nå ønsket kroppsvekt")
        default:
            return tr("My measurement goal: ", "Mitt kroppsmål: ") + metric.name
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("A MEASURABLE GOAL", "ET MÅLBART MÅL"))
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(tr("Follow your body measurements",
                                "Følg utviklingen i kroppsmålene dine"))
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                        Text(tr(
                            "Record a starting point, choose a realistic target and check in occasionally. Your measurements remain private.",
                            "Registrer et utgangspunkt, velg et realistisk mål og mål på nytt underveis. Målingene dine er private."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 13) {
                        Text(tr("What do you want to track?", "Hva ønsker du å følge?"))
                            .font(.headline)
                        Picker(tr("Measurement", "Kroppsmål"), selection: $metric) {
                            ForEach(ATHLTHBodyMetric.allCases) { kind in
                                Text(kind.name).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(suggestedTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(tr(
                            "You can choose a smaller or larger target. Progress is calculated from measurements, not appearance.",
                            "Du velger om målet skal være lavere eller høyere. Fremgangen beregnes fra registrerte mål, ikke utseende."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                        HStack(spacing: 12) {
                            measurementField(
                                tr("Current measurement", "Ditt startmål"),
                                text: $baselineText
                            )
                            measurementField(
                                tr("Desired measurement", "Ønsket mål"),
                                text: $targetText
                            )
                        }
                        DatePicker(tr("Target date", "Måldato"),
                                   selection: $deadline,
                                   in: Date()...,
                                   displayedComponents: .date)
                            .font(.subheadline)
                    }
                    .padding(16)
                    .athlthPlanCard(radius: 19)

                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("Measurement check-ins", "Måleinnsjekker"),
                              systemImage: "calendar.badge.clock")
                            .font(.headline)
                        Text(tr(
                            "ATHLTH will invite you to record another measurement on the way to your target date. Every check-in updates your chart and gives a brief trend-based response.",
                            "ATHLTH minner deg på å måle på nytt frem mot måldatoen. Hver innsjekk oppdaterer grafen og gir en kort tilbakemelding på utviklingen."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        Picker(tr("How often?", "Hvor ofte?"), selection: $interval) {
                            Text(tr("Every week", "Hver uke")).tag(7)
                            Text(tr("Every 2 weeks", "Hver 2. uke")).tag(14)
                            Text(tr("Every month", "Hver måned")).tag(30)
                        }
                        .pickerStyle(.segmented)
                        Toggle(tr("Remind me on my phone", "Send påminnelse til telefonen"),
                               isOn: $enableNotifications)
                            .font(.subheadline)
                        Text(tr(
                            "Check-ins appear in Activity. Phone notifications require notification permission and never show your measurements or injuries on the lock screen.",
                            "Innsjekk vises i Aktivitet. Telefonvarsler krever varslingstillatelse og viser aldri kroppsmål eller skader på låseskjermen."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(16)
                    .athlthPlanCard(radius: 19)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(action: saveGoal) {
                        Label(tr("Create measurement goal", "Opprett kroppsmål"),
                              systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHPlanDesign.accentInk)
                    .disabled(number(baselineText) == nil || number(targetText) == nil)
                }
                .padding(17)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("New measurement goal", "Nytt kroppsmål"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
        }
        .onAppear(perform: fillPreviousMeasurement)
        .onChange(of: metric) { _, _ in
            baselineText = ""
            targetText = ""
            fillPreviousMeasurement()
        }
    }

    private func measurementField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            HStack {
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                Text(metric.unit)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(11)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fillPreviousMeasurement() {
        let profile = ATHLTHTrainingProfile.load(userID: session.profile.userID)
        if let previous = profile.latest(metric) {
            baselineText = String(format: "%.1f", previous.value)
        }
    }

    private func saveGoal() {
        guard let baseline = number(baselineText),
              let target = number(targetText),
              metric.range.contains(baseline), metric.range.contains(target),
              baseline != target else {
            errorMessage = tr(
                "Enter valid, different current and target measurements.",
                "Oppgi gyldige og forskjellige start- og måleverdier."
            )
            return
        }
        let now = Date()
        var profile = ATHLTHTrainingProfile.load(userID: session.profile.userID)
        guard profile.record(metric: metric, value: baseline, at: now) else { return }
        profile.save(userID: session.profile.userID)
        let goal = ATHLTHGoal(
            title: suggestedTitle,
            category: .body,
            startDate: now,
            deadline: deadline,
            privacy: .privateOnly,
            dataSource: .manual,
            bodyMeasurementGoal: ATHLTHBodyGoalConfiguration(
                metric: metric, baseline: baseline, target: target,
                checkInIntervalDays: interval,
                notificationsEnabled: enableNotifications
            )
        )
        goalStore.add(goal)
        NotificationCenter.default.post(name: .athlthTrainingDataDidChange, object: nil)
        if enableNotifications {
            let userID = session.profile.userID
            let currentGoals = goalStore.goals
            Task {
                let allowed = await notifications
                    .requestSystemNotificationPermissionIfNeeded()
                guard allowed, session.profile.userID == userID else { return }
                await ATHLTHBodyGoalReminderScheduler.sync(
                    goals: currentGoals, profile: profile, userID: userID
                )
            }
        }
        dismiss()
        onCreated?()
    }
}

/// The same screen is reached from the goal detail and an Activity reminder.
struct ATHLTHBodyGoalCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    let goal: ATHLTHGoal
    @State private var reading = ""
    @State private var measuredAt = Date()
    @State private var error: String?
    @State private var savedFeedback: String?

    private var config: ATHLTHBodyGoalConfiguration? { goal.bodyMeasurementGoal }

    var body: some View {
        NavigationStack {
            Form {
                if let config {
                    Section {
                        Text(ATHLTHLocalization.choose(
                            english: "A small check-in is enough. Measure the same place and under similar conditions each time.",
                            norwegian: "En kort innsjekk er nok. Mål samme sted og under omtrent like forhold hver gang."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        HStack {
                            Text(config.metric.name)
                            Spacer()
                            TextField(config.metric.unit, text: $reading)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 95)
                            Text(config.metric.unit)
                                .foregroundStyle(.secondary)
                        }
                        DatePicker(
                            ATHLTHLocalization.choose(english: "Date", norwegian: "Dato"),
                            selection: $measuredAt,
                            in: goal.startDate...Date(),
                            displayedComponents: .date
                        )
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "YOUR MEASUREMENT",
                            norwegian: "DIN MÅLING"
                        ))
                    }
                    if let savedFeedback {
                        Section {
                            Label(savedFeedback, systemImage: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Measurement check-in", norwegian: "Måleinnsjekk"
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) { save() }
                    .disabled(config == nil || savedFeedback != nil)
                }
            }
        }
    }

    private func save() {
        guard let config,
              let value = Double(reading.replacingOccurrences(of: ",", with: ".")),
              config.metric.range.contains(value) else {
            error = ATHLTHLocalization.choose(
                english: "Enter a valid measurement.",
                norwegian: "Skriv inn et gyldig kroppsmål."
            )
            return
        }
        var profile = ATHLTHTrainingProfile.load(userID: session.profile.userID)
        guard profile.record(metric: config.metric, value: value, at: measuredAt)
        else { return }
        profile.save(userID: session.profile.userID)
        savedFeedback = ATHLTHBodyGoalCheckInPolicy.feedback(goal, profile: profile)
        NotificationCenter.default.post(name: .athlthTrainingDataDidChange, object: nil)
    }
}

struct ATHLTHBodyGoalProgressView: View {
    let goal: ATHLTHGoal
    @EnvironmentObject private var session: AppSessionStore
    @State private var profile = ATHLTHTrainingProfile()
    @State private var showingCheckIn = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var configuration: ATHLTHBodyGoalConfiguration? {
        goal.bodyMeasurementGoal
    }

    var body: some View {
        if let configuration {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(tr("MEASUREMENT PROGRESS", "UTVIKLING I KROPPSMÅL"),
                          systemImage: "chart.xyaxis.line")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Spacer()
                    Text(configuration.metric.unit)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                HStack {
                    numberTile(tr("Starting point", "Startmål"), configuration.baseline,
                               configuration.metric.unit)
                    numberTile(tr("Latest", "Siste"), profile.latest(configuration.metric)?.value,
                               configuration.metric.unit)
                    numberTile(tr("Target", "Mål"), configuration.target,
                               configuration.metric.unit)
                }
                ProgressView(value: ATHLTHBodyGoalCheckInPolicy.progress(
                    goal, profile: profile
                ))
                .tint(ATHLTHPlanDesign.accentInk)

                Text(ATHLTHBodyGoalCheckInPolicy.feedback(goal, profile: profile))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                let points = profile.readings(for: configuration.metric)
                    .filter { $0.date >= goal.startDate }
                if points.count > 1 {
                    Chart(points) { value in
                        LineMark(x: .value("Date", value.date),
                                 y: .value(configuration.metric.unit, value.value))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        PointMark(x: .value("Date", value.date),
                                  y: .value(configuration.metric.unit, value.value))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                    .frame(height: 165)
                }
                if goal.status == .active {
                    Button {
                        showingCheckIn = true
                    } label: {
                        Label(tr("Record a check-in", "Registrer innsjekk"),
                              systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHPlanDesign.accentInk)
                }
                Text(tr(
                    "A measured trend, not a daily judgment. Changes can be gradual and non-linear.",
                    "Følg trenden over tid, ikke enkeltdager. Utvikling kan være gradvis og variere."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(16)
            .athlthPlanCard(radius: 19)
            .sheet(isPresented: $showingCheckIn) {
                ATHLTHBodyGoalCheckInView(goal: goal)
            }
            .onAppear(perform: load)
            .onReceive(NotificationCenter.default.publisher(
                for: .athlthTrainingDataDidChange
            )) { _ in load() }
        }
    }

    private func numberTile(_ label: String, _ number: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(number.map { String(format: "%.1f %@", $0, unit) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private func load() {
        profile = ATHLTHTrainingProfile.load(userID: session.profile.userID)
    }
}
