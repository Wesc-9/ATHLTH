import SwiftUI
import MapKit

struct IPhoneWorkoutView: View {
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmFinish = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Keep your iPhone with you throughout the workout. GPS measures distance and pace outdoors. Heart rate and calories are not estimated.")
                }
                if let workout = recorder.active {
                    Section(workout.title) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = workout.elapsed(at: context.date)
                            LabeledContent("Active time", value: Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                            LabeledContent("Distance", value: settings.measurementPreference.distance(fromKilometers: workout.distanceMeters / 1000))
                            if workout.distanceMeters >= 50 {
                                LabeledContent("Average pace", value: String(format: "%.1f min/%@", elapsed / 60 / (workout.distanceMeters / (settings.measurementPreference == .metric ? 1000 : 1609.344)), settings.measurementPreference.distanceUnit))
                            }
                        }
                        if workout.resumedAt == nil { Button("Resume workout") { recorder.resume() } }
                        else { Button("Pause workout") { recorder.pause() } }
                        Button("Finish & save", role: .destructive) {
                            confirmFinish = true
                        }
                        .disabled(recorder.saving)
                    }

                    if let liveSession = realtime.currentSession,
                       realtime.isSharingLiveLocation {
                        Section("Live") {
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: liveSession
                                )
                            } label: {
                                Label(
                                    liveSession.ghostChallengeID == nil
                                        ? "View live workout"
                                        : "View live Ghost Run",
                                    systemImage:
                                        "location.circle.fill"
                                )
                            }

                            Text(
                                liveSession.ghostChallengeID == nil
                                    ? "Your latest position is shared only with the audience selected in Social Privacy."
                                    : "This Ghost Run live position is private to the race participants."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let last = workout.points.last {
                        Section("Current GPS position") {
                            Map(initialPosition: .region(MKCoordinateRegion(center: last.location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                                Marker("Latest position", coordinate: last.location.coordinate)
                            }.frame(height: 220)
                        }
                    }
                }
                if let message = recorder.message { Section { Text(message).font(.footnote) } }
                Section("Saved iPhone workouts") {
                    ForEach(recorder.history.prefix(20)) { workout in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(workout.title).font(.headline)
                            Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                            Text(String(format: "%.2f km · %.0f min", workout.distanceMeters / 1000, workout.accumulatedSeconds / 60))
                            if workout.healthID == nil {
                                Button("Copy to Apple Health") {
                                    Task { await health.requestAuthorization(); await recorder.retryHealthSave(workout) }
                                }.disabled(recorder.saving)
                            } else { Label("Saved to Apple Health", systemImage: "checkmark.circle").font(.caption) }
                        }
                    }
                }
            }
            .navigationTitle("iPhone workout")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog(
                "Finish this workout?",
                isPresented: $confirmFinish,
                titleVisibility: .visible
            ) {
                Button("Finish & save") {
                    Task {
                        await recorder.finish()
                        await realtime
                            .leaveCurrentLiveWorkout()
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(
                        for: .seconds(5)
                    )

                    guard !Task.isCancelled else {
                        break
                    }

                    recorder.checkpoint()
                    await publishLivePointIfNeeded()
                }
            }
        }
    }

    @MainActor
    private func publishLivePointIfNeeded() async {
        guard let workout = recorder.active,
              workout.resumedAt != nil,
              let lastPoint =
                workout.points.last?
                    .location
        else {
            return
        }

        if realtime.currentSession == nil {
            guard social.privacy?
                    .shareLiveWorkoutLocation ==
                    true
            else {
                return
            }

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title: workout.title,
                    activity:
                        workout.walking
                            ? "walking"
                            : "running",
                    visibility: visibility
                )
        }

        await realtime.publishLocation(
            lastPoint,
            distanceMeters:
                workout.distanceMeters,
            elapsedSeconds:
                workout.elapsed(at: Date())
        )
    }
    }
}
