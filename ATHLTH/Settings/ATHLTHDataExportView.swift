import Foundation
import SwiftUI

private struct ATHLTHExportPreferences: Codable {
    let measurement: String
    let defaultActivityVisibility: String
    let shareRoutesByDefault: Bool
    let hideRouteStartAndEnd: Bool
    let shareHeartRateByDefault: Bool
    let preferredWorkoutCapture: String
    let defaultStrengthTracking: String
    let autoPublishCompletedWorkouts: Bool
    let backgroundHealthSyncEnabled: Bool
}

private struct ATHLTHDataExportEnvelope: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let profile: UserProfile
    let activePlan: TrainingPlan?
    let planTemplates: [TrainingPlan]
    let savedWorkoutTemplates: [PlannedSession]
    let savedRoutes: [TrainingRoute]
    let preferences: ATHLTHExportPreferences
    let note: String
}

struct ATHLTHDataExportView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isPreparing = false

    var body: some View {
        Form {
            Section("Included") {
                Label("ATHLTH profile", systemImage: "person")
                Label("Training plans and templates", systemImage: "calendar")
                Label("Saved workout templates", systemImage: "dumbbell")
                Label("Saved routes", systemImage: "map")
                Label("App preferences", systemImage: "slider.horizontal.3")
            }

            Section {
                Text("Apple Health / HealthKit data is not included. Health data remains under Apple’s Health permissions and export controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share ATHLTH Export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    Button {
                        Task { await prepareExport() }
                    } label: {
                        HStack {
                            Label("Prepare Export", systemImage: "arrow.down.doc")
                            Spacer()
                            if isPreparing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isPreparing)
                }

                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if exportURL == nil {
                await prepareExport()
            }
        }
    }

    @MainActor
    private func prepareExport() async {
        isPreparing = true
        exportError = nil
        defer { isPreparing = false }

        let payload = ATHLTHDataExportEnvelope(
            schemaVersion: 1,
            exportedAt: Date(),
            profile: session.profile,
            activePlan: session.activePlan,
            planTemplates: session.planTemplates,
            savedWorkoutTemplates: session.savedWorkoutTemplates,
            savedRoutes: session.savedRoutes,
            preferences: ATHLTHExportPreferences(
                measurement: settings.measurementPreference.rawValue,
                defaultActivityVisibility: settings.defaultActivityVisibility.rawValue,
                shareRoutesByDefault: settings.shareRoutesByDefault,
                hideRouteStartAndEnd: settings.hideRouteStartAndEnd,
                shareHeartRateByDefault: settings.shareHeartRateByDefault,
                preferredWorkoutCapture: settings.preferredWorkoutCapture.rawValue,
                defaultStrengthTracking: settings.defaultStrengthTracking.rawValue,
                autoPublishCompletedWorkouts: settings.autoPublishCompletedWorkouts,
                backgroundHealthSyncEnabled: settings.backgroundHealthSyncEnabled
            ),
            note: "This export contains ATHLTH-owned app data only. Apple Health / HealthKit data is intentionally excluded."
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(payload)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let filename = "ATHLTH-export-\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportError = "ATHLTH could not prepare the export: \(error.localizedDescription)"
        }
    }
}
