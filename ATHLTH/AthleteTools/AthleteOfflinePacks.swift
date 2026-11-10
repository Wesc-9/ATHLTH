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

    /// Account-scoped thumbnail index. A route grid must not decode every
    /// offline pack manifest for every cell, or return a previous account's image.
    private static var routeSnapshotIndexOwner: UUID?
    private static var routeSnapshotFileIndex: [UUID: URL] = [:]
    private static let routeSnapshotImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 20
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    private static func invalidateRouteSnapshotIndex() {
        routeSnapshotIndexOwner = nil
        routeSnapshotFileIndex.removeAll(keepingCapacity: false)
        routeSnapshotImages.removeAllObjects()
    }

    private static func indexRouteSnapshots(for userID: UUID) {
        guard routeSnapshotIndexOwner != userID else { return }
        routeSnapshotFileIndex.removeAll(keepingCapacity: false)
        routeSnapshotImages.removeAllObjects()
        routeSnapshotIndexOwner = userID

        let signpost = ATHLTHPerformance.begin("OfflineRouteSnapshotIndex")
        defer { ATHLTHPerformance.end("OfflineRouteSnapshotIndex", id: signpost) }
        guard let root = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }
        let folder = root
            .appendingPathComponent("AthleteOfflinePacks", isDirectory: true)
            .appendingPathComponent(userID.uuidString, isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ) else { return }

        var newest: [UUID: (date: Date, file: URL)] = [:]
        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  let data = try? Data(
                    contentsOf: directory.appendingPathComponent("pack.json")
                  ),
                  let manifest = try? JSONDecoder().decode(
                    AthleteOfflinePack.self, from: data
                  ) else { continue }
            for routeID in manifest.mapRouteIDs {
                let file = directory.appendingPathComponent(routeID.uuidString + ".png")
                guard FileManager.default.fileExists(atPath: file.path),
                      manifest.routes.contains(where: { $0.id == routeID })
                else { continue }
                if let current = newest[routeID],
                   current.date >= manifest.downloadedAt { continue }
                newest[routeID] = (date: manifest.downloadedAt, file: file)
            }
        }
        routeSnapshotFileIndex = newest.mapValues { $0.file }
    }

    private func root(_ id: UUID) throws -> URL {
        var url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AthleteOfflinePacks", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true; try url.setResourceValues(resources)
        return url
    }
    func load(userID: UUID) {
        Self.invalidateRouteSnapshotIndex()
        accountID = userID; packs = []; error = nil
        do {
            let folder = try root(userID)
            let children = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )
            // Recover a previous pack after a process kill between moving
            // the old directory aside and installing the new directory.
            for child in children where child.lastPathComponent.hasPrefix("previous-") {
                let metadata = child.appendingPathComponent("pack.json")
                guard let bytes = try? Data(contentsOf: metadata),
                      let previousPack = try? JSONDecoder().decode(
                        AthleteOfflinePack.self, from: bytes
                      ) else { continue }
                let destination = folder.appendingPathComponent(
                    previousPack.id.uuidString, isDirectory: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: child)
                } else {
                    try? FileManager.default.moveItem(at: child, to: destination)
                }
            }
            for child in try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            ) {
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
    /// Forget which account is active without deleting its encrypted local
    /// files. A later sign-in to that account can load them again.
    func clearActiveAccount() {
        Self.invalidateRouteSnapshotIndex()
        accountID = nil
        packs = []
        error = nil
    }

    /// Reuse previously prepared map tiles in the normal route library,
    /// not only in the now-hidden manual offline-pack view. The manifest
    /// prevents loading an unrelated exercise image with the same UUID.
    static func cachedRouteSnapshot(routeID: UUID, userID: UUID) -> UIImage? {
        let signpost = ATHLTHPerformance.begin("OfflineRouteSnapshotLookup")
        defer { ATHLTHPerformance.end("OfflineRouteSnapshotLookup", id: signpost) }
        indexRouteSnapshots(for: userID)
        guard let path = routeSnapshotFileIndex[routeID] else { return nil }
        let key = "\(userID.uuidString)|\(routeID.uuidString)" as NSString
        if let cached = routeSnapshotImages.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path.path) else { return nil }
        routeSnapshotImages.setObject(
            image, forKey: key,
            cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        )
        return image
    }

    func remove(_ pack: AthleteOfflinePack) {
        guard let accountID else { return }
        do {
            try FileManager.default.removeItem(
                at: root(accountID).appendingPathComponent(pack.id.uuidString)
            )
            packs.removeAll { $0.id == pack.id }
            Self.invalidateRouteSnapshotIndex()
        } catch {
            self.error = "The offline pack could not be deleted."
        }
    }
    func download(plan: TrainingPlan, routes: [TrainingRoute], userID: UUID, includeMedia: Bool = true) async {
        guard !downloading else { return }
        // A previous network failure must not block a new local-first save.
        error = nil
        downloading = true; defer { downloading = false }
        let startedAt = Date()
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
            // Reuse existing media before attempting network work. A save
            // should not redownload assets already safely on the device.
            let previousDirectory = folder.appendingPathComponent(
                plan.id.uuidString, isDirectory: true
            )
            let previousMetadata = previousDirectory.appendingPathComponent("pack.json")
            let previousPack: AthleteOfflinePack? = {
                guard let bytes = try? Data(contentsOf: previousMetadata) else {
                    return nil
                }
                return try? JSONDecoder().decode(
                    AthleteOfflinePack.self, from: bytes
                )
            }()
            func routeUnchanged(_ id: UUID) -> Bool {
                guard let old = previousPack?.routes.first(where: { $0.id == id }),
                      let updated = selectedRoutes.first(where: { $0.id == id })
                else { return false }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                guard let oldData = try? encoder.encode(old),
                      let nextData = try? encoder.encode(updated)
                else { return false }
                return oldData == nextData
            }

            func reuseAsset(_ id: UUID, availableIDs: [UUID]) throws -> Bool {
                guard availableIDs.contains(id) else { return false }
                let name = id.uuidString + ".png"
                let source = previousDirectory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    return false
                }
                try FileManager.default.copyItem(
                    at: source, to: temporary.appendingPathComponent(name)
                )
                return true
            }
            if includeMedia { for route in selectedRoutes {
                if routeUnchanged(route.id),
                   try reuseAsset(
                       route.id, availableIDs: previousPack?.mapRouteIDs ?? []
                   ) {
                    pack.mapRouteIDs.append(route.id)
                    continue
                }
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
            }
            var seen = Set<UUID>()
            if includeMedia { for exercise in sessions.flatMap(\.exercises) where seen.insert(exercise.id).inserted {
                try Task.checkCancellation()
                if try reuseAsset(
                    exercise.id,
                    availableIDs: previousPack?.exerciseImageIDs ?? []
                ) {
                    pack.exerciseImageIDs.append(exercise.id)
                    continue
                }
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
            }
            if includeMedia {
                // A failed image/map refresh must not delete previously
                // downloaded files. Keep only assets referenced by this plan.
                let existing = folder.appendingPathComponent(
                    plan.id.uuidString, isDirectory: true
                )
                let metadata = existing.appendingPathComponent("pack.json")
                if let data = try? Data(contentsOf: metadata),
                   let previous = try? JSONDecoder().decode(
                    AthleteOfflinePack.self, from: data
                   ) {
                    for assetID in Set(previous.mapRouteIDs + previous.exerciseImageIDs) {
                        let name = assetID.uuidString + ".png"
                        let source = existing.appendingPathComponent(name)
                        let target = temporary.appendingPathComponent(name)
                        guard !FileManager.default.fileExists(atPath: target.path),
                              FileManager.default.fileExists(atPath: source.path)
                        else { continue }
                        try FileManager.default.copyItem(at: source, to: target)
                        if previous.mapRouteIDs.contains(assetID),
                           routeUnchanged(assetID) {
                            pack.mapRouteIDs.append(assetID)
                        }
                        if previous.exerciseImageIDs.contains(assetID),
                           sessions.flatMap(\.exercises).contains(where: {
                            $0.id == assetID
                           }) {
                            pack.exerciseImageIDs.append(assetID)
                        }
                    }
                }
                pack.mapRouteIDs = Array(Set(pack.mapRouteIDs))
                pack.exerciseImageIDs = Array(Set(pack.exerciseImageIDs))
            }
            if !includeMedia {
                // Keep only media belonging to this revision of the plan.
                // Old routes and removed exercises must not remain in the
                // saved manifest after an offline edit.
                let allowedExerciseIDs = Set(
                    sessions.flatMap(\.exercises).map(\.id)
                )
                let oldRouteIDs = Set(previousPack?.mapRouteIDs ?? [])
                let oldImageIDs = Set(previousPack?.exerciseImageIDs ?? [])
                for assetID in oldRouteIDs.intersection(routeIDs)
                    where routeUnchanged(assetID) {
                    if try reuseAsset(
                        assetID, availableIDs: previousPack?.mapRouteIDs ?? []
                    ) {
                        pack.mapRouteIDs.append(assetID)
                    }
                }
                for assetID in oldImageIDs.intersection(allowedExerciseIDs) {
                    if try reuseAsset(
                        assetID, availableIDs: previousPack?.exerciseImageIDs ?? []
                    ) {
                        pack.exerciseImageIDs.append(assetID)
                    }
                }
                // Missing media will be assessed during enrichment, rather
                // than carrying over an outdated count from another plan.
                pack.missingAssets = 0
            }
            try Task.checkCancellation()
            try JSONEncoder().encode(pack).write(to: temporary.appendingPathComponent("pack.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let destination = folder.appendingPathComponent(plan.id.uuidString)
            // A media refresh can take minutes. Never let an older in-flight
            // snapshot overwrite a newer local save on iPhone or iPad.
            let latestMetadata = destination.appendingPathComponent("pack.json")
            if let latestBytes = try? Data(contentsOf: latestMetadata),
               let latest = try? JSONDecoder().decode(
                AthleteOfflinePack.self, from: latestBytes
               ),
               latest.downloadedAt > startedAt {
                throw CancellationError()
            }
            // Replace directory packs with a rollback path. A failed update
            // must not destroy the last usable offline plan and media.
            let previous = folder.appendingPathComponent(
                "previous-" + UUID().uuidString, isDirectory: true
            )
            let hadPrevious = FileManager.default.fileExists(atPath: destination.path)
            if hadPrevious {
                try FileManager.default.moveItem(at: destination, to: previous)
            }
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
                staging = nil
                if hadPrevious {
                    try? FileManager.default.removeItem(at: previous)
                }
            } catch {
                if hadPrevious {
                    try? FileManager.default.moveItem(at: previous, to: destination)
                }
                throw error
            }
            guard accountID == userID else { return }
            load(userID: userID)
        } catch is CancellationError {
            // An obsolete enrichment task must not surface as a save error.
        } catch {
            if !Task.isCancelled {
                self.error = "The download could not be completed. Your existing pack has been preserved."
            }
        }
        if let staging { try? FileManager.default.removeItem(at: staging) }
    }
}

struct AthleteOfflineView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @StateObject private var offline = AthleteOfflinePackStore()
    @State private var selectedPlanID: UUID?

    // Shared SwiftUI view on iPhone and iPad. Retry unfinished media when
    // either device's scene becomes active, not just on first navigation.
    private func resumeMissingMedia() async {
        guard !offline.downloading else { return }
        for saved in offline.packs {
            guard !Task.isCancelled else { return }
            guard let current = session.trainingPlans.first(where: {
                $0.id == saved.plan.id
            }) else { continue }
            let sessions = current.weeks.flatMap(\.days).flatMap(\.sessions)
            let routeIDs = Set(
                sessions.compactMap(\.routeID) +
                sessions.compactMap { $0.runningWorkout?.routeID } +
                sessions.flatMap { $0.runningWorkouts ?? [] }.compactMap(\.routeID)
            )
            let expectedRoutes = session.savedRoutes.filter {
                routeIDs.contains($0.id) && $0.coordinates.count >= 2
            }.count
            let expectedImages = Set(
                sessions.flatMap(\.exercises)
                    .filter { $0.embeddedExercise.imageURL?.scheme == "https" }
                    .map(\.id)
            ).count
            guard saved.mapRouteIDs.count < expectedRoutes ||
                  saved.exerciseImageIDs.count < expectedImages else { continue }
            await offline.download(
                plan: current, routes: session.savedRoutes,
                userID: session.profile.userID, includeMedia: true
            )
        }
    }

    var body: some View {
        List {
            Section(ATHLTHLocalization.choose(
                english: "Save a plan", norwegian: "Lagre en plan"
            )) {
                Picker(ATHLTHLocalization.choose(
                    english: "Plan", norwegian: "Plan"
                ), selection: $selectedPlanID) {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a plan", norwegian: "Velg en plan"
                    )).tag(nil as UUID?)
                    ForEach(session.trainingPlans) {
                        Text($0.title).tag(Optional($0.id))
                    }
                }
                Button(ATHLTHLocalization.choose(
                    english: "Save", norwegian: "Lagre"
                )) {
                    guard let plan = session.trainingPlans.first(where: {
                        $0.id == selectedPlanID
                    }) else { return }
                    let userID = session.profile.userID
                    Task {
                        // Save essential plan data first, regardless of network.
                        await offline.download(
                            plan: plan, routes: session.savedRoutes,
                            userID: userID, includeMedia: false
                        )
                        guard offline.error == nil else { return }
                        // Enrich with images and map snapshots when possible.
                        // If offline, the local plan remains available.
                        await offline.download(
                            plan: plan, routes: session.savedRoutes,
                            userID: userID, includeMedia: true
                        )
                    }
                }
                .disabled(offline.downloading || selectedPlanID == nil)
                if offline.downloading {
                    ProgressView(ATHLTHLocalization.choose(
                        english: "Saving…", norwegian: "Lagrer…"
                    ))
                }
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
            .task(id: session.profile.userID) {
                offline.load(userID: session.profile.userID)
                await resumeMissingMedia()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await resumeMissingMedia() }
            }
            .alert("Offline packs", isPresented: Binding(get: { offline.error != nil }, set: { if !$0 { offline.error = nil } })) {
                Button("OK") { offline.error = nil }
            } message: { Text(offline.error ?? "") }
    }
}
private struct AthleteOfflinePackView: View {
    @EnvironmentObject private var appSession: AppSessionStore
    let pack: AthleteOfflinePack
    @ObservedObject var offline: AthleteOfflinePackStore
    var body: some View {
        List {
            ForEach(pack.plan.weeks.flatMap(\.days).flatMap(\.sessions)) { session in
                Section(session.title) {
                    // A downloaded snapshot can outlive a deleted or edited
                    // live plan. Only offer live controls for the matching
                    // current session; never silently open stale workout data.
                    if let currentPlan = appSession.trainingPlans.first(where: {
                        $0.id == pack.plan.id
                    }),
                    let currentSession = currentPlan.weeks.flatMap(\.days)
                        .flatMap(\.sessions).first(where: { $0.id == session.id }) {
                        NavigationLink("Open workout controls") {
                            PlannedWorkoutDetailView(
                                planID: currentPlan.id,
                                workout: currentSession,
                                isHealthCompleted: false
                            )
                        }
                    } else {
                        Text("Saved offline copy · read-only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
