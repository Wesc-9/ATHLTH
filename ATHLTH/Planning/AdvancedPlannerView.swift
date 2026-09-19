import SwiftUI

struct AdvancedPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @State private var showingSessionEditor = false
    @State private var selectedDayID: UUID?

    var body: some View {
        VStack(spacing: 16) {
            if let plan = session.activePlan {
                ATHLTHCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.title2.weight(.bold))
                            Text("Version \(plan.version) · \(plan.visibility.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            session.addWeekToActivePlan()
                        } label: {
                            Label("Add week", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                ForEach(plan.weeks) { week in
                    ATHLTHCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Week \(week.weekNumber)")
                                    .font(.headline)
                                Text(week.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(week.days.reduce(0) { $0 + $1.sessions.count }) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 12) {
                            ForEach(week.days) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(day.title)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Button {
                                            selectedDayID = day.id
                                            showingSessionEditor = true
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.green)
                                    }

                                    if day.sessions.isEmpty {
                                        Text("Rest / recovery day")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(day.sessions) { workout in
                                            HStack(spacing: 10) {
                                                Image(systemName: workout.kind.systemImage)
                                                    .foregroundStyle(.green)
                                                    .frame(width: 26)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(workout.title)
                                                        .font(.subheadline.weight(.medium))
                                                    Text(sessionSummary(workout))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Button(role: .destructive) {
                                                    session.removeSession(workout.id, fromDay: day.id)
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .font(.caption)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No active plan",
                    systemImage: "calendar.badge.plus",
                    description: Text("Create a training plan to start planning weeks and sessions.")
                )

                Button("Create starter plan") {
                    session.createStarterPlan()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .sheet(isPresented: $showingSessionEditor) {
            if let selectedDayID {
                SessionEditorView(dayID: selectedDayID)
                    .environmentObject(session)
            }
        }
    }

    private func sessionSummary(_ workout: PlannedSession) -> String {
        var parts: [String] = []

        if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }

        if let distance = workout.targetDistanceKilometers {
            parts.append(String(format: "%.1f km", distance))
        }

        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
        }

        return parts.isEmpty ? workout.kind.title : parts.joined(separator: " · ")
    }
}

struct TrainingPlanManagerView: View {
    @EnvironmentObject private var session: AppSessionStore

    var body: some View {
        VStack(spacing: 16) {
            if let plan = session.activePlan {
                ATHLTHCard {
                    ATHLTHSectionHeader(title: "Plan settings")
                    VStack(spacing: 12) {
                        LabeledContent("Plan", value: plan.title)
                        LabeledContent("Version", value: "\(plan.version)")
                        LabeledContent("Weeks", value: "\(plan.weeks.count)")
                        LabeledContent("Visibility", value: plan.visibility.title)
                    }
                    .padding(.top, 10)
                }

                ATHLTHCard {
                    ATHLTHSectionHeader(title: "Advanced planning")
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Multiple sessions per day", systemImage: "square.stack.3d.up.fill")
                        Label("Strength, run, walk, mobility and recovery", systemImage: "figure.mixed.cardio")
                        Label("Routes and playlists per session", systemImage: "map.fill")
                        Label("Sets, reps, load, RPE and rest", systemImage: "dumbbell.fill")
                        Label("Nutrition can attach to the same calendar later", systemImage: "fork.knife")
                    }
                    .font(.subheadline)
                    .padding(.top, 10)
                }

                Button {
                    session.duplicateActivePlan()
                } label: {
                    Label("Duplicate as template", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }
}

struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let dayID: UUID

    @State private var title = "New Workout"
    @State private var kind: WorkoutKind = .strength
    @State private var durationMinutes = 45
    @State private var distanceKilometers = 5.0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $title)

                    Picker("Type", selection: $kind) {
                        ForEach(WorkoutKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }

                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)

                    if kind == .running || kind == .walking {
                        Stepper(
                            "Distance: \(distanceKilometers, specifier: "%.1f") km",
                            value: $distanceKilometers,
                            in: 0.5...100,
                            step: 0.5
                        )
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Later in this editor") {
                    Label("Route selection / GPX route", systemImage: "map")
                    Label("Exercise builder with sets, reps, weight and RPE", systemImage: "dumbbell")
                    Label("Spotify workout playlist", systemImage: "music.note")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Add Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        session.addSession(
                            PlannedSession(
                                id: UUID(),
                                title: title,
                                kind: kind,
                                scheduledStart: nil,
                                durationMinutes: durationMinutes,
                                targetDistanceKilometers: kind == .running || kind == .walking ? distanceKilometers : nil,
                                targetPaceSecondsPerKilometer: nil,
                                routeID: nil,
                                exercises: [],
                                notes: notes.isEmpty ? nil : notes,
                                spotifyPlaylistURI: nil
                            ),
                            toDay: dayID
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
