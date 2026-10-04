import Foundation
import ImageIO
import MapKit
import SwiftUI
import UIKit

struct AthleteOfflinePack: Identifiable, Codable {
    var id: UUID { plan.id }
    var plan: TrainingPlan
    var routes: [TrainingRoute]
    var downloadedAt: Date
    var mapRouteIDs: [UUID]
    var exerciseImageIDs: [UUID]
    var missingAssets: Int
}

@MainActor
final class AthleteOfflinePackStore: ObservableObject {
    @Published private(set) var packs: [AthleteOfflinePack] = []
    @Published private(set) var downloading = false
    @Published var error: String?
    private var accountID: UUID?

    private func root(_ id: UUID) throws -> URL {
        var url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AthleteOfflinePacks", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true; try url.setResourceValues(resources)
        return url
    }
    func load(userID: UUID) {
        accountID = userID; packs = []; error = nil
        do {
            let folder = try root(userID)
            for child in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                guard UUID(uuidString: child.lastPathComponent) != nil else { continue }
                let file = child.appendingPathComponent("pack.json")
                if let data = try? Data(contentsOf: file), let pack = try? JSONDecoder().decode(AthleteOfflinePack.self, from: data) { packs.append(pack) }
            }
            packs.sort { $0.downloadedAt > $1.downloadedAt }
        } catch { self.error = "Saved offline packs could not be opened." }
    }
    func image(packID: UUID, assetID: UUID) -> UIImage? {
        guard let accountID, let folder = try? root(accountID) else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(packID.uuidString).appendingPathComponent(assetID.uuidString + ".png").path)
    }
    func remove(_ pack: AthleteOfflinePack) {
        guard let accountID else { return }
        do { try FileManager.default.removeItem(at: root(accountID).appendingPathComponent(pack.id.uuidString)); packs.removeAll { $0.id == pack.id } }
        catch { self.error = "The offline pack could not be deleted." }
    }
    func download(plan: TrainingPlan, routes: [TrainingRoute], userID: UUID) async {
        guard !downloading else { return }
        downloading = true; defer { downloading = false }
        var staging: URL?
        do {
            let folder = try root(userID)
            let temporary = folder.appendingPathComponent("download-" + UUID().uuidString, isDirectory: true)
            staging = temporary
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            let sessions = plan.weeks.flatMap(\.days).flatMap(\.sessions)
            let routeIDs = Set(sessions.compactMap(\.routeID) + sessions.compactMap { $0.runningWorkout?.routeID } + sessions.flatMap { $0.runningWorkouts ?? [] }.compactMap(\.routeID))
            let selectedRoutes = routes.filter { routeIDs.contains($0.id) }
            var pack = AthleteOfflinePack(plan: plan, routes: selectedRoutes, downloadedAt: Date(), mapRouteIDs: [], exerciseImageIDs: [], missingAssets: 0)
            for route in selectedRoutes {
                try Task.checkCancellation()
                let coordinates = route.coordinates.map(\.coordinate).filter(CLLocationCoordinate2DIsValid)
                guard coordinates.count >= 2 else { pack.missingAssets += 1; continue }
                let options = MKMapSnapshotter.Options()
                var rect = MKMapRect.null
                for coordinate in coordinates { let point = MKMapPoint(coordinate); rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1)) }
                options.mapRect = rect.insetBy(dx: -max(rect.width * 0.15, 200), dy: -max(rect.height * 0.15, 200))
                options.size = CGSize(width: 900, height: 600)
                options.scale = 1
                do {
                    let snapshot = try await MKMapSnapshotter(options: options).start()
                    let rendered = UIGraphicsImageRenderer(size: options.size).image { _ in
                        snapshot.image.draw(at: .zero)
                        let path = UIBezierPath()
                        for (index, coordinate) in coordinates.enumerated() {
                            let point = snapshot.point(for: coordinate)
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        UIColor.systemBlue.setStroke(); path.lineWidth = 4; path.stroke()
                    }
                    guard let png = rendered.pngData() else { throw CocoaError(.fileWriteUnknown) }
                    try png.write(to: temporary.appendingPathComponent(route.id.uuidString + ".png"), options: .atomic)
                    pack.mapRouteIDs.append(route.id)
                } catch { if Task.isCancelled { throw CancellationError() }; pack.missingAssets += 1 }
            }
            var seen = Set<UUID>()
            for exercise in sessions.flatMap(\.exercises) where seen.insert(exercise.id).inserted {
                try Task.checkCancellation()
                guard let url = exercise.embeddedExercise.imageURL, url.scheme == "https" else { continue }
                do {
                    let (bytes, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 5_000_000,
                          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1024,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary), let png = UIImage(cgImage: thumbnail).pngData() else { throw CocoaError(.fileReadCorruptFile) }
                    try png.write(to: temporary.appendingPathComponent(exercise.id.uuidString + ".png"), options: .atomic)
                    pack.exerciseImageIDs.append(exercise.id)
                } catch { if Task.isCancelled { throw CancellationError() }; pack.missingAssets += 1 }
            }
            try Task.checkCancellation()
            try JSONEncoder().encode(pack).write(to: temporary.appendingPathComponent("pack.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let destination = folder.appendingPathComponent(plan.id.uuidString)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: destination) }
            staging = nil
            guard accountID == userID else { return }
            load(userID: userID)
        } catch { if !Task.isCancelled { self.error = "The download could not be completed. Your existing pack has been preserved." } }
        if let staging { try? FileManager.default.removeItem(at: staging) }
    }
}

struct AthleteOfflineView: View {
    @EnvironmentObject private var session: AppSessionStore
    @StateObject private var offline = AthleteOfflinePackStore()
    @State private var selectedPlanID: UUID?
    var body: some View {
        List {
            Section("Download a plan") {
                Picker("Plan", selection: $selectedPlanID) {
                    Text("Choose a plan").tag(nil as UUID?)
                    ForEach(session.trainingPlans) { Text($0.title).tag(Optional($0.id)) }
                }
                Button("Download for offline use") {
                    guard let plan = session.trainingPlans.first(where: { $0.id == selectedPlanID }) else { return }
                    let userID = session.profile.userID
                    Task { await offline.download(plan: plan, routes: session.savedRoutes, userID: userID) }
                }.disabled(offline.downloading || selectedPlanID == nil)
                if offline.downloading { ProgressView("Downloading plan, instructions, images and route snapshots…") }
            }
            Section("On this device") {
                ForEach(offline.packs) { pack in
                    NavigationLink {
                        AthleteOfflinePackView(pack: pack, offline: offline)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(pack.plan.title)
                            Text("\(pack.downloadedAt.formatted(date: .abbreviated, time: .shortened)) · \(pack.missingAssets) unavailable assets").font(.caption)
                        }
                    }.swipeActions { Button("Delete", role: .destructive) { offline.remove(pack) } }
                }
            }
            Section {
                Text("Downloaded plans, embedded exercise instructions, images and route snapshots work without a connection. Maps cover only the downloaded route area and are static snapshots; navigation, streamed video, AI and social features require a connection. Existing local workout logging and cloud-backup settings continue to control workout syncing.")
            }
        }.navigationTitle("Offline packs")
            .task(id: session.profile.userID) { offline.load(userID: session.profile.userID) }
            .alert("Offline packs", isPresented: Binding(get: { offline.error != nil }, set: { if !$0 { offline.error = nil } })) {
                Button("OK") { offline.error = nil }
            } message: { Text(offline.error ?? "") }
    }
}
private struct AthleteOfflinePackView: View {
    let pack: AthleteOfflinePack
    @ObservedObject var offline: AthleteOfflinePackStore
    var body: some View {
        List {
            ForEach(pack.plan.weeks.flatMap(\.days).flatMap(\.sessions)) { session in
                Section(session.title) {
                    NavigationLink("Open workout controls") {
                        PlannedWorkoutDetailView(planID: pack.plan.id, workout: session, isHealthCompleted: false)
                    }
                    if let notes = session.notes { Text(notes) }
                    if let duration = session.durationMinutes { Text("\(duration) min") }
                    if let distance = session.targetDistanceKilometers { Text("\(distance, specifier: "%.1f") km") }
                    ForEach(session.runningWorkouts ?? session.runningWorkout.map { [$0] } ?? []) { workout in
                        Text(workout.title).font(.headline)
                        Text(workout.summary)
                        ForEach(workout.blocks) { block in
                            Text("\(block.title) · \(block.repetitions)× \(targetText(block.work))")
                            if let recovery = block.recovery { Text("Recovery: \(targetText(recovery))").font(.caption) }
                            if let notes = block.notes { Text(notes).font(.caption) }
                        }
                    }
                    ForEach(session.exercises) { exercise in
                        VStack(alignment: .leading) {
                            Text(exercise.embeddedExercise.name).font(.headline)
                            Text("\(exercise.sets) sets · \(exercise.reps ?? 0) reps")
                            if let image = offline.image(packID: pack.id, assetID: exercise.id) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180) }
                            ForEach(Array(exercise.embeddedExercise.instructions.enumerated()), id: \.offset) { _, instruction in Text(instruction) }
                        }
                    }
                }
            }
            ForEach(pack.routes) { route in
                Section(route.title) {
                    if let image = offline.image(packID: pack.id, assetID: route.id) { Image(uiImage: image).resizable().scaledToFit() }
                    else { Text("A map snapshot is not available in this pack.") }
                }
            }
        }.navigationTitle(pack.plan.title)
    }
    private func targetText(_ target: RunningStepTarget) -> String {
        var pieces: [String] = []
        if let distance = target.distanceMeters { pieces.append(String(format: "%.0f m", distance)) }
        if let duration = target.durationSeconds { pieces.append(String(format: "%.1f min", duration / 60)) }
        if let rpe = target.intensity.rpe { pieces.append(String(format: "RPE %.0f", rpe)) }
        if let zone = target.intensity.heartRateZone { pieces.append("HR zone \(zone)") }
        if let pace = target.intensity.paceMinSecondsPerKilometer { pieces.append(String(format: "Pace %.0f sec/km", pace)) }
        if pieces.isEmpty { pieces.append(target.intensity.kind.title) }
        return pieces.joined(separator: " · ")
    }
}
