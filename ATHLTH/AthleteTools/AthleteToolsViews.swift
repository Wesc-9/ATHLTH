import SwiftUI

struct AthleteToolsView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject private var tools = AthleteToolsStore.shared

    var body: some View {
        Group {
            if session.signedIn {
                List {
                    NavigationLink("Race calendar & preparation", systemImage: "flag.checkered") { AthleteRaceCalendarView() }
                    NavigationLink("Training load", systemImage: "chart.xyaxis.line") { AthleteLoadView() }
                    NavigationLink("Strength progression", systemImage: "scalemass") {
                        List {
                            Text("During a strength workout, progression hints use your previous working sets, reps and RPE/RIR. Tap Use to accept a suggestion.")
                            Text("Warm-up sets are excluded. Very high effort can suggest a reduction; missing effort data keeps the current load.")
                        }.navigationTitle("Strength progression")
                    }
                    NavigationLink("Offline training packs", systemImage: "arrow.down.circle") { AthleteOfflineView() }
                    NavigationLink("Fuel & hydration", systemImage: "drop") { AthleteFuelView() }
                    NavigationLink("Private cycle diary", systemImage: "lock.shield") { AthleteCycleView() }
                    NavigationLink("Gear maintenance", systemImage: "wrench.and.screwdriver") { AthleteGearMaintenanceView() }
                    NavigationLink("Coach sharing", systemImage: "person.badge.shield.checkmark") { AthleteCoachView() }
                    NavigationLink("Training partners", systemImage: "person.2") { AthletePartnerView() }
                    Section("Route sharing") {
                        Text("Each workout's sharing screen includes route privacy and an optional preview. Routes stay private until you choose to include a map.")
                    }
                }
            } else {
                ContentUnavailableView("Sign in to use Athlete Tools", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("Athlete Tools")
        .task(id: session.signedIn ? session.profile.userID : nil) {
            await tools.switchAccount(session.signedIn ? session.profile.userID : nil)
        }
        .id(session.signedIn ? session.profile.userID : nil)
        .alert("Athlete Tools", isPresented: Binding(get: { tools.error != nil }, set: { if !$0 { tools.error = nil } })) {
            Button("OK") { tools.error = nil }
        } message: { Text(tools.error ?? "") }
    }
}

struct AthleteRaceCalendarView: View {
    @ObservedObject private var tools = AthleteToolsStore.shared
    @State private var name = ""
    @State private var date = Date().addingTimeInterval(30 * 86_400)
    @State private var distance = 10.0
    @State private var goal = ""
    @State private var adaptation: AthleteRace?

    var body: some View {
        Form {
            Section("Add competition") {
                TextField("Race name", text: $name)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Distance (km)", value: $distance, format: .number).keyboardType(.decimalPad)
                TextField("Your goal", text: $goal)
                Button("Save race") {
                    tools.data.races.append(AthleteRace(name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)), date: date, distanceKM: distance, goal: String(goal.prefix(500))))
                    name = ""; goal = ""
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !distance.isFinite || distance <= 0 || distance > 1000)
            }
            Section("Your races") {
                ForEach(tools.data.races.sorted { $0.date < $1.date }) { race in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(race.name).font(.headline)
                        Text("\(race.date.formatted(date: .abbreviated, time: .omitted)) · \(race.distanceKM, specifier: "%.1f") km")
                        Text(race.phase(at: Date())).foregroundStyle(.secondary)
                        if !race.goal.isEmpty { Text(race.goal) }
                        Button("Review plan adjustment") { adaptation = race }
                        Button("Delete", role: .destructive) { tools.data.races.removeAll { $0.id == race.id } }
                    }
                }
            }
            Section { Text("Phases show the final 14 days as taper and the first 7 days after a race as recovery. Plan adjustments are proposed for your review and use the existing AI consent settings.") }
        }.navigationTitle("Race calendar")
            .sheet(item: $adaptation) { race in CoachPlanAdaptationView(initialNotes: race.adaptationNotes) }
    }
}

enum AthleteLoadSource {
    @MainActor static func assess(health: HealthKitManager, strength: StrengthWorkoutStore) -> AthleteLoadAssessment {
        let history = strength.workoutHistory.filter(\.isFinished)
        let linkedIDs = Set(history.compactMap { $0.healthMetrics.healthKitWorkoutUUID })
        var samples = health.workouts.filter { !linkedIDs.contains($0.id) }.map {
            AthleteLoadSample(date: $0.startDate, minutes: $0.duration / 60, effort: 4)
        }
        samples += history.map { workout in
            let effort = workout.exercises.flatMap(\.sets).filter(\.countsTowardTrainingLoad).compactMap { set -> Double? in
                if let rpe = set.rpe, rpe.isFinite { return min(10, max(1, rpe)) }
                if let rir = set.rir, rir.isFinite { return min(10, max(1, 10 - rir)) }
                return nil
            }
            return AthleteLoadSample(date: workout.startedAt, minutes: max(0, (workout.endedAt ?? workout.startedAt).timeIntervalSince(workout.startedAt)) / 60,
                effort: effort.isEmpty ? 4 : effort.reduce(0, +) / Double(effort.count))
        }
        return AthleteLoadEngine.assess(samples, recoveryScore: health.recovery.score)
    }
}
struct AthleteLoadView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @ObservedObject private var tools = AthleteToolsStore.shared
    private var assessment: AthleteLoadAssessment { AthleteLoadSource.assess(health: health, strength: strength) }
    var body: some View {
        Form {
            Section("Last 7 days") {
                LabeledContent("Estimated load", value: String(format: "%.0f", assessment.current))
                if let ratio = assessment.ratio {
                    LabeledContent("Compared with weekly baseline", value: String(format: "%.0f%%", ratio * 100))
                    Label(assessment.shouldWarn ? "Review the recent increase" : "No rapid increase detected", systemImage: assessment.shouldWarn ? "exclamationmark.triangle" : "checkmark.circle")
                } else { Text("Record training in each of the previous three weeks to establish a baseline.") }
                if assessment.lowRecovery { Text("Your current recovery score is low. Consider it when planning your next workout.") }
            }
            Section {
                Toggle("Notify about a load increase", isOn: Binding(get: { tools.data.loadNotifications }, set: { enabled in
                    Task { let allowed = enabled ? await tools.requestNotifications() : true; if allowed { tools.data.loadNotifications = enabled } }
                }))
                Text("Load = minutes × effort. Strength uses recorded RPE/RIR; other sessions and missing ratings use an estimated effort of 4/10. The baseline is the previous 21 days divided by three. Linked HealthKit strength workouts are counted once. A 30% increase prompts a review. These estimates do not diagnose injury or illness.")
            }
        }.navigationTitle("Training load")
    }
}

struct AthleteFuelView: View {
    @ObservedObject private var tools = AthleteToolsStore.shared
    @State private var start = Date()
    var body: some View {
        Form {
            Section("Your plan") {
                Stepper("Duration: \(tools.data.fuel.durationMinutes) min", value: $tools.data.fuel.durationMinutes, in: 30...480, step: 10)
                Stepper("Remind every \(tools.data.fuel.intervalMinutes) min", value: $tools.data.fuel.intervalMinutes, in: 10...60, step: 5)
                Stepper("Carbohydrate: \(tools.data.fuel.carbohydrateGramsPerHour) g/h", value: $tools.data.fuel.carbohydrateGramsPerHour, in: 0...120, step: 5)
                Stepper("Fluid: \(tools.data.fuel.fluidMLPerHour) ml/h", value: $tools.data.fuel.fluidMLPerHour, in: 0...1500, step: 50)
                Text("Per reminder: \(tools.data.fuel.gramsPerReminder, specifier: "%.0f") g · \(tools.data.fuel.fluidPerReminder, specifier: "%.0f") ml")
                DatePicker("Start", selection: $start, in: Date()...)
                Button("Start reminders") { Task { await tools.startFuelReminders(at: start) } }
                Button("Stop reminders", role: .destructive) { Task { await tools.stopFuelReminders() } }
                if let end = tools.fuelEndsAt, end > Date() { Text("Scheduled until \(end.formatted(date: .abbreviated, time: .shortened))") }
            }
            Section("Reminder schedule") {
                ForEach(tools.data.fuel.reminderOffsets, id: \.self) { Text("\($0) minutes after start") }
            }
            Section { Text("Choose amounts appropriate to your own needs. These are editable planning defaults. Reminders are iPhone notifications and may mirror to Apple Watch according to your notification settings; no independent Watch timer is started. Stop reminders when your workout ends or pauses.") }
        }.navigationTitle("Fuel & hydration")
    }
}

struct AthleteCycleView: View {
    @ObservedObject private var tools = AthleteToolsStore.shared
    @State private var date = Date()
    @State private var energy = 3
    @State private var symptoms = ""
    @State private var notes = ""
    @State private var confirmingDelete = false
    var body: some View {
        Form {
            Section("Private on this device") {
                Text("This diary is stored in a protected file excluded from device backups. It is not sent to the feed, coach, AI or cloud backup. Signing out clears the visible diary; entries remain on this device for your account until you delete them.")
            }
            Section("New entry") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Stepper("Energy: \(energy)/5", value: $energy, in: 1...5)
                TextField("Symptoms (optional)", text: $symptoms, axis: .vertical)
                TextField("Your experience (optional)", text: $notes, axis: .vertical)
                Button("Save privately") {
                    tools.replaceCycleEntries(tools.cycleEntries + [AthleteCycleEntry(date: date, energy: energy, symptoms: String(symptoms.prefix(2000)), notes: String(notes.prefix(2000)))])
                    symptoms = ""; notes = ""
                }
            }
            Section("Entries") {
                ForEach(tools.cycleEntries) { entry in
                    VStack(alignment: .leading) {
                        Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · Energy \(entry.energy)/5").font(.headline)
                        if !entry.symptoms.isEmpty { Text(entry.symptoms) }
                        if !entry.notes.isEmpty { Text(entry.notes) }
                    }
                }.onDelete { offsets in
                    var entries = tools.cycleEntries; entries.remove(atOffsets: offsets); tools.replaceCycleEntries(entries)
                }
                Button("Delete all diary entries", role: .destructive) { confirmingDelete = true }
            }
        }.navigationTitle("Private cycle diary")
            .confirmationDialog("Delete all diary entries on this device?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { tools.replaceCycleEntries([]) }
            }
            .privacySensitive()
    }
}

struct AthleteGearMaintenanceView: View {
    @EnvironmentObject private var gear: ProfileGearStore
    @ObservedObject private var tools = AthleteToolsStore.shared
    var body: some View {
        List {
            if gear.items.isEmpty { Text("Add gear to your profile to set maintenance intervals.") }
            ForEach(gear.items) { item in
                NavigationLink(item.name) { AthleteGearRuleView(item: item) }
            }
        }.navigationTitle("Gear maintenance")
    }
}
private struct AthleteGearRuleView: View {
    let item: ProfileGearItem
    @EnvironmentObject private var gear: ProfileGearStore
    @ObservedObject private var tools = AthleteToolsStore.shared
    @State private var interval = 500.0
    @State private var notifications = false
    @State private var note = ""
    private var km: Double { gear.usageStats(for: item).totalDistanceMeters / 1000 }
    var body: some View {
        Form {
            Section("Maintenance interval") {
                LabeledContent("Total registered use", value: String(format: "%.1f km", km))
                TextField("Interval (km)", value: $interval, format: .number).keyboardType(.decimalPad)
                Toggle("Notify when service is due", isOn: $notifications)
                Button("Save interval") {
                    Task {
                        let allowed = notifications ? await tools.requestNotifications() : true
                        guard allowed else { return }
                        let baseline = tools.data.gearRules[item.id]?.baselineKM ?? 0
                        tools.data.gearRules[item.id] = AthleteGearRule(intervalKM: interval, baselineKM: baseline, notifications: notifications)
                        await tools.checkGear(gear)
                    }
                }.disabled(!interval.isFinite || interval <= 0 || interval > 100_000)
                if let rule = tools.data.gearRules[item.id] {
                    Text(rule.remaining(at: km) <= 0 ? "Service is due" : String(format: "%.1f km until service", rule.remaining(at: km)))
                }
            }
            Section("Record service") {
                TextField("Work performed", text: $note)
                Button("Record service at current mileage") {
                    tools.data.services.append(AthleteGearService(gearID: item.id, date: Date(), odometerKM: km, note: String(note.prefix(1000))))
                    if var rule = tools.data.gearRules[item.id] { rule.baselineKM = km; rule.notified = false; tools.data.gearRules[item.id] = rule }
                    note = ""
                }
            }
            Section("Service history") {
                ForEach(tools.data.services.filter { $0.gearID == item.id }.sorted { $0.date > $1.date }) { service in
                    Text("\(service.date.formatted(date: .abbreviated, time: .omitted)) · \(service.odometerKM, specifier: "%.1f") km\n\(service.note)")
                }
            }
        }.navigationTitle(item.name).task {
            interval = tools.data.gearRules[item.id]?.intervalKM ?? gear.detailRecords[item.id]?.replacementTargetKM ?? 500
            notifications = tools.data.gearRules[item.id]?.notifications ?? false
        }
    }
}

struct AthleteToolsRuntimeObserver: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var tools = AthleteToolsStore.shared
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .task(id: session.signedIn ? session.profile.userID : nil) {
                await tools.switchAccount(session.signedIn ? session.profile.userID : nil)
                await refresh()
            }
            .onChange(of: gear.usageRecords) { _, _ in Task { await refresh() } }
            .onChange(of: health.workouts) { _, _ in Task { await refresh() } }
            .onChange(of: strength.workoutHistory) { _, _ in Task { await refresh() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }
    private func refresh() async {
        guard session.signedIn, tools.userID == session.profile.userID else { return }
        await tools.checkGear(gear)
        await tools.checkLoad(AthleteLoadSource.assess(health: health, strength: strength))
    }
}
