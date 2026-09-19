import SwiftUI

struct PersonalHealthProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager

    @State private var includeDateOfBirth = false
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var includeSex = false
    @State private var healthSex: HealthSex = .preferNotToSay
    @State private var includeWeight = false
    @State private var weightKilograms = 75.0
    @State private var includeHeight = false
    @State private var heightCentimeters = 180.0

    var body: some View {
        Form {
            Section("Source") {
                LabeledContent(
                    "Current source",
                    value: sourceTitle
                )

                Button {
                    Task {
                        await health.requestAuthorization()
                        await health.refreshPersonalDetails()
                        session.updatePersonalDetails(
                            health.personalDetails,
                            source: health.personalDetails.hasAnyValue ? .appleHealth : .none
                        )
                        loadFromSession()
                    }
                } label: {
                    Label("Use Apple Health", systemImage: "heart.fill")
                }

                Text("ATHLTH uses only profile values Apple Health makes available. Missing values can be entered manually below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Manual details") {
                Toggle("Date of birth", isOn: $includeDateOfBirth)

                if includeDateOfBirth {
                    DatePicker(
                        "Date",
                        selection: $dateOfBirth,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                Toggle("Sex for health calculations", isOn: $includeSex)

                if includeSex {
                    Picker("Sex", selection: $healthSex) {
                        ForEach(HealthSex.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }

                Toggle("Weight", isOn: $includeWeight)

                if includeWeight {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(String(format: "%.1f kg", weightKilograms))
                            .monospacedDigit()
                    }
                    Slider(value: $weightKilograms, in: 30...250, step: 0.5)
                }

                Toggle("Height", isOn: $includeHeight)

                if includeHeight {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(heightCentimeters)) cm")
                            .monospacedDigit()
                    }
                    Slider(value: $heightCentimeters, in: 120...230, step: 1)
                }

                Button("Save manual details") {
                    session.updatePersonalDetails(
                        HealthProfileBasics(
                            dateOfBirth: includeDateOfBirth ? dateOfBirth : nil,
                            healthSex: includeSex ? healthSex : nil,
                            weightKilograms: includeWeight ? weightKilograms : nil,
                            heightCentimeters: includeHeight ? heightCentimeters : nil
                        ),
                        source: .manual
                    )
                }
                .disabled(
                    !includeDateOfBirth &&
                    !includeSex &&
                    !includeWeight &&
                    !includeHeight
                )
            }

            Section("Privacy") {
                Text("These values are private profile data. They are not shown on your public profile unless ATHLTH later adds a separate, explicit sharing control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Personal & Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFromSession()
        }
    }

    private var sourceTitle: String {
        switch session.onboardingProfile?.personalDetailsSource ?? .none {
        case .appleHealth: return "Apple Health"
        case .manual: return "Manual"
        case .none: return "Not set"
        }
    }

    private func loadFromSession() {
        guard let profile = session.onboardingProfile else { return }

        if let value = profile.dateOfBirth {
            includeDateOfBirth = true
            dateOfBirth = value
        } else {
            includeDateOfBirth = false
        }

        if let value = profile.healthSex {
            includeSex = true
            healthSex = value
        } else {
            includeSex = false
        }

        if let value = profile.weightKilograms {
            includeWeight = true
            weightKilograms = value
        } else {
            includeWeight = false
        }

        if let value = profile.heightCentimeters {
            includeHeight = true
            heightCentimeters = value
        } else {
            includeHeight = false
        }
    }
}

struct SpotifySettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Spotify") {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.spotifyConnected ? "Spotify connected" : "Spotify not connected")
                            .font(.headline)
                        Text("Used only for training-plan playlists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Button(settings.spotifyConnected ? "Disconnect Spotify" : "Connect Spotify") {
                    settings.spotifyConnected.toggle()
                }
            }

            Section("Training-plan behavior") {
                Toggle(
                    "Autoplay linked playlist when workout starts",
                    isOn: $settings.spotifyAutoplayLinkedPlaylists
                )
                .disabled(!settings.spotifyConnected)

                Text("Playlists are selected inside a training plan. ATHLTH does not expose Spotify as a general music player, and quick-start workouts without a plan do not get a Spotify binding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("How it works") {
                Label("Connect Spotify here", systemImage: "1.circle.fill")
                Label("Open a training plan and choose a playlist", systemImage: "2.circle.fill")
                Label("Start a workout from that plan", systemImage: "3.circle.fill")
                Label("ATHLTH launches the linked playlist", systemImage: "4.circle.fill")
            }

            Section {
                Text("The current connection button is a development placeholder. The production version will use Spotify authorization and App Remote.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spotify")
        .navigationBarTitleDisplayMode(.inline)
    }
}
