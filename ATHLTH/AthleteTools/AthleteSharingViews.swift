import SwiftUI

struct AthleteCoachView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @StateObject private var service = AthleteSharingService()
    @State private var coachID: UUID?
    @State private var workouts = false
    @State private var plan = false
    @State private var readiness = false
    var body: some View {
        List {
            Section("Invite a coach") {
                Picker("Someone you follow", selection: $coachID) {
                    Text("Choose a coach").tag(nil as UUID?)
                    ForEach(social.visibleProfiles.filter { social.followingIDs.contains($0.userID) }) { Text($0.resolvedName).tag(Optional($0.userID)) }
                }
                Toggle("Selected workout summaries", isOn: $workouts)
                Toggle("Plan summary", isOn: $plan)
                Toggle("Recovery score", isOn: $readiness)
                Text("Nothing is sent until the coach accepts and you publish a snapshot. GPS, diary entries and detailed Health records are excluded.").font(.caption)
                Button("Send invitation") {
                    guard let coachID else { return }
                    Task { await service.run { try await service.manage("request", coach: coachID, workouts: workouts, plan: plan, readiness: readiness) } }
                }.disabled(coachID == nil || service.busy)
            }
            Section("Connections") {
                ForEach(service.connections) { connection in
                    NavigationLink {
                        AthleteCoachConnectionView(connection: connection, service: service)
                    } label: {
                        let otherID = connection.athleteID == session.profile.userID ? connection.coachID : connection.athleteID
                        VStack(alignment: .leading) {
                            Text(social.profile(for: otherID)?.resolvedName ?? "ATHLTH athlete")
                            Text("\(connection.athleteID == session.profile.userID ? "Your coach" : "Your athlete") · \(connection.state)").font(.caption)
                        }
                    }
                }
            }
            if let error = service.error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("Coach sharing")
            .task(id: session.profile.userID) { await service.run { try await service.loadConnections() } }
            .refreshable { await service.run { try await service.loadConnections() } }
    }
}

private struct AthleteCoachConnectionView: View {
    let connection: AthleteCoachConnection
    @ObservedObject var service: AthleteSharingService
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: AthleteCoachSnapshot?
    @State private var feedback: [AthleteCoachFeedback] = []
    @State private var shareWorkouts = false
    @State private var sharePlan = false
    @State private var shareReadiness = false
    @State private var selected = Set<UUID>()
    @State private var bodyText = ""
    @State private var proposal = false
    @State private var reviewing: AthleteCoachFeedback?
    @State private var confirmingRevoke = false
    private var current: AthleteCoachConnection { service.connections.first { $0.id == connection.id } ?? connection }
    private var isAthlete: Bool { current.athleteID == session.profile.userID }
    private var availableWorkouts: [(id: UUID, value: AthleteSharedWorkout)] {
        let history = strength.workoutHistory.filter(\.isFinished)
        let linked = Set(history.compactMap { $0.healthMetrics.healthKitWorkoutUUID })
        let healthRows = health.workouts.filter { !linked.contains($0.id) }.map { workout in
            (date: workout.startDate, id: workout.id, value: AthleteSharedWorkout(title: workout.activity.rawValue, activity: workout.activity.rawValue,
             date: workout.startDate.ISO8601Format(), minutes: String(Int(workout.duration / 60))))
        }
        let strengthRows = history.map { workout in
            (date: workout.startedAt, id: workout.id, value: AthleteSharedWorkout(title: workout.title, activity: "Strength",
             date: workout.startedAt.ISO8601Format(), minutes: String(Int(max(0, (workout.endedAt ?? workout.startedAt).timeIntervalSince(workout.startedAt)) / 60))))
        }
        return (healthRows + strengthRows).sorted { $0.date > $1.date }.prefix(20).map { (id: $0.id, value: $0.value) }
    }
    private var planSummary: String? {
        guard let plan = session.activePlan else { return nil }
        let sessions = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        return plan.title + "\n" + sessions.map { "\($0.title) · \($0.scheduledStart?.ISO8601Format() ?? "Unscheduled") · \($0.durationMinutes ?? 0) min" }.joined(separator: "\n")
    }
    var body: some View {
        Form {
            Section("Connection") {
                Text(current.state.capitalized)
                if !isAthlete && current.state == "pending" {
                    Button("Accept coach invitation") { Task { await service.run { try await service.manage("accept", connection: current.id) }; await reload() } }
                }
                if current.state != "revoked" {
                    Button("Revoke connection", role: .destructive) { confirmingRevoke = true }
                }
            }
            if isAthlete && current.state != "revoked" {
                Section("Your consent") {
                    Toggle("Selected workout summaries", isOn: $shareWorkouts)
                    Toggle("Plan summary", isOn: $sharePlan)
                    Toggle("Recovery score", isOn: $shareReadiness)
                    Button("Save sharing permissions") {
                        Task { await service.run { try await service.manage("scopes", connection: current.id, workouts: shareWorkouts, plan: sharePlan, readiness: shareReadiness) }; await reload() }
                    }
                    Text("Saving permissions immediately removes the old snapshot. Publish a new snapshot when ready.").font(.caption)
                }
                if current.state == "active" {
                    if current.shareWorkouts {
                        Section("Choose workouts to publish") {
                            ForEach(availableWorkouts, id: \.id) { row in
                                Toggle("\(row.value.title) · \(row.value.date.prefix(10)) · \(row.value.minutes) min", isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } }))
                            }
                        }
                    }
                    Section("Snapshot preview") {
                        if current.sharePlan { Text(planSummary ?? "No active plan") }
                        if current.shareReadiness { Text("Recovery score: \(health.recovery.score.map(String.init) ?? "Unavailable")") }
                        Text("\(current.shareWorkouts ? selected.count : 0) selected workout summaries. No route, heart rate or diary data.")
                        Button("Publish this snapshot to coach") {
                            Task { await service.run {
                                try await service.publish(current.id, plan: current.sharePlan ? planSummary : nil,
                                    workouts: current.shareWorkouts ? availableWorkouts.filter { selected.contains($0.id) }.map(\.value) : [],
                                    readiness: current.shareReadiness ? health.recovery.score : nil)
                            }; await reload() }
                        }
                    }
                }
            }
            if current.state == "active" {
                if let snapshot {
                    Section("Shared snapshot · \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))") {
                        if let plan = snapshot.planText { Text(plan) }
                        ForEach(Array((snapshot.workouts ?? []).enumerated()), id: \.offset) { _, workout in
                            Text("\(workout.title) · \(workout.date.prefix(10)) · \(workout.minutes) min")
                        }
                        if let readiness = snapshot.readinessScore { Text("Recovery score: \(readiness)") }
                    }
                }
                Section("Comments & proposals") {
                    TextField("Message", text: $bodyText, axis: .vertical)
                    if !isAthlete { Toggle("Plan change proposal", isOn: $proposal) }
                    Button("Send") { Task { await service.run { try await service.sendFeedback(connection: current.id, kind: proposal && !isAthlete ? "proposal" : "comment", body: bodyText, author: session.profile.userID); bodyText = "" }; await reload() } }
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.count > 4000)
                    ForEach(feedback) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.kind.capitalized).font(.caption)
                            Text(entry.body)
                            if isAthlete && entry.kind == "proposal" {
                                Button("Review plan proposal") { reviewing = entry }
                            }
                        }
                    }
                }
            }
            if let error = service.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Coach connection").disabled(service.busy)
            .task { shareWorkouts = current.shareWorkouts; sharePlan = current.sharePlan; shareReadiness = current.shareReadiness; await reload() }
            .refreshable { await service.run { try await service.loadConnections() }; await reload() }
            .sheet(item: $reviewing) { entry in CoachPlanAdaptationView(initialNotes: "My trainer proposed this change. Prepare changes for my review; do not apply them without approval:\n" + entry.body) }
            .confirmationDialog("Revoke access and delete the shared snapshot and feedback?", isPresented: $confirmingRevoke, titleVisibility: .visible) {
                Button("Revoke", role: .destructive) {
                    Task { await service.run { try await service.manage("revoke", connection: current.id); snapshot = nil; feedback = []; dismiss() } }
                }
            }
    }
    private func reload() async {
        snapshot = nil; feedback = []
        await service.run {
            snapshot = try await service.loadSnapshot(current.id)
            feedback = try await service.loadFeedback(current.id)
        }
    }
}

struct AthletePartnerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @StateObject private var service = AthleteSharingService()
    @State private var start = Date().addingTimeInterval(3600)
    @State private var duration = 60
    @State private var area = ""
    @State private var sport = "running"
    @State private var level = "intermediate"
    @State private var consent = false
    private var end: Date { start.addingTimeInterval(Double(duration) * 60) }
    private var normalizedArea: String { area.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var valid: Bool { (2...80).contains(normalizedArea.count) && start > Date() && start < Date().addingTimeInterval(30 * 86_400) }
    var body: some View {
        List {
            Section("Availability") {
                TextField("City or broad area", text: $area)
                Picker("Activity", selection: $sport) { ForEach(["running","walking","cycling","strength","swimming"], id: \.self) { Text($0.capitalized).tag($0) } }
                Picker("Level", selection: $level) { ForEach(["beginner","intermediate","advanced"], id: \.self) { Text($0.capitalized).tag($0) } }
                DatePicker("Start", selection: $start, in: Date()...Date().addingTimeInterval(30 * 86_400))
                Stepper("Duration: \(duration) min", value: $duration, in: 15...240, step: 15)
                Toggle("Publish this availability", isOn: $consent)
                Text("Your area, activity, level and time are visible to signed-in athletes who may see your profile. Use a broad area, never your home address. Contact still needs approval through the existing profile and invite controls.").font(.caption)
                Button("Publish availability") {
                    let slot = AthletePartnerSlot(userID: session.profile.userID, startsAt: start, endsAt: end, area: normalizedArea, sport: sport, level: level, enabled: true)
                    Task { await service.run { try await service.publishSlot(slot) } }
                }.disabled(!valid || !consent || service.busy)
                Button("Find overlapping training partners") {
                    Task { await service.run { try await service.findMatches(userID: session.profile.userID, sport: sport, area: normalizedArea, level: level, start: start, end: end) } }
                }.disabled(!valid || service.busy)
            }
            Section("Matches") {
                ForEach(service.matches) { slot in
                    NavigationLink { FriendProfileView(userID: slot.userID) } label: {
                        VStack(alignment: .leading) {
                            Text(social.profile(for: slot.userID)?.resolvedName ?? "ATHLTH athlete")
                            Text("\(slot.area.capitalized) · \(slot.startsAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        }
                    }
                }
                if service.matches.isEmpty { Text("No matches loaded. Search by area, activity, level and overlapping time.").font(.caption) }
            }
            Section("Your published availability") {
                ForEach(service.ownSlots) { slot in
                    VStack(alignment: .leading) {
                        Text("\(slot.sport.capitalized) · \(slot.area.capitalized)")
                        Text(slot.startsAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        Button("Withdraw", role: .destructive) { Task { await service.run { try await service.removeSlot(slot) } } }
                    }
                }
            }
            if let error = service.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Training partners")
            .task(id: session.profile.userID) { await service.run { try await service.loadSlots(userID: session.profile.userID) } }
    }
}
