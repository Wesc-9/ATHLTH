import Foundation
import FoundationXML

/// Imports *planned* workouts into the canonical editable block timeline.
/// Recorded FIT/TCX activities are not silently turned into prescriptions.
/// No external service, health permission, or uploaded attachment is required.
enum ATHLTHWorkoutFileImport {
    struct Preview: Identifiable {
        let id = UUID()
        let sourceName: String
        let title: String
        let activity: ATHLTHPlannedWorkoutType
        let blocks: [WorkoutTemplateBlock]

        var durationSeconds: TimeInterval? {
            let all = blocks.compactMap(\.durationSeconds)
            guard all.count == blocks.count else { return nil }
            return all.reduce(0, +)
        }
    }

    enum ImportFailure: LocalizedError {
        case unsupported
        case oversized
        case invalidFile
        case noPlannedWorkout
        case incompatibleActivity
        case tooManySteps

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return ATHLTHLocalization.choose(
                    english: "Choose a planned workout (.tcx, .zwo or ATHLTH .json). Recorded .fit files and routes must be imported separately.",
                    norwegian: "Velg en planlagt treningsøkt (.tcx, .zwo eller ATHLTH .json). Registrerte .fit-økter og ruter importeres separat.")
            case .oversized:
                return ATHLTHLocalization.choose(
                    english: "The file is too large (max 2 MB).",
                    norwegian: "Filen er for stor (maks 2 MB).")
            case .invalidFile:
                return ATHLTHLocalization.choose(
                    english: "The file is not a valid structured workout. No changes were made.",
                    norwegian: "Filen inneholder ikke en gyldig strukturert treningsøkt. Ingen endringer er gjort.")
            case .noPlannedWorkout:
                return ATHLTHLocalization.choose(
                    english: "This looks like a recorded activity, not a planned workout. Import a workout with editable steps instead.",
                    norwegian: "Dette ser ut som en registrert aktivitet, ikke en planlagt økt. Importer en treningsøkt med redigerbare deler.")
            case .incompatibleActivity:
                return ATHLTHLocalization.choose(
                    english: "The file contains a different sport. Choose the matching workout type before importing.",
                    norwegian: "Filen inneholder en annen treningsform. Velg riktig økttype før import.")
            case .tooManySteps:
                return ATHLTHLocalization.choose(
                    english: "The imported workout has too many steps (max 256).",
                    norwegian: "Den importerte økten har for mange deler (maks 256).")
            }
        }
    }

    static func load(
        url: URL,
        selectedActivity: ATHLTHPlannedWorkoutType?
    ) throws -> Preview {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let extensionName = url.pathExtension.lowercased()
        guard ["tcx", "zwo", "json"].contains(extensionName) else {
            throw ImportFailure.unsupported
        }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 2_000_000 {
            throw ImportFailure.oversized
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count <= 2_000_000 else {
            throw ImportFailure.oversized
        }
        return try parse(
            data: data,
            filename: url.lastPathComponent,
            selectedActivity: selectedActivity
        )
    }

    /// Pure entry point used by tests and iPhone/iPad file imports.
    static func parse(
        data: Data,
        filename: String,
        selectedActivity: ATHLTHPlannedWorkoutType?
    ) throws -> Preview {
        guard data.count <= 2_000_000, !data.isEmpty else {
            throw ImportFailure.oversized
        }
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        let decoded: (title: String, activity: ATHLTHPlannedWorkoutType, blocks: [WorkoutTemplateBlock])
        switch fileExtension {
        case "json":
            let decoder = JSONDecoder()
            if let envelope = try? decoder.decode(JSONWorkout.self, from: data) {
                let activity = envelope.activity.flatMap {
                    ATHLTHPlannedWorkoutType(rawValue: $0.lowercased())
                } ?? inferredActivity(envelope.blocks)
                decoded = (envelope.title, activity, envelope.blocks)
            } else if let blocks = try? decoder.decode([WorkoutTemplateBlock].self, from: data) {
                decoded = ("Imported workout", inferredActivity(blocks), blocks)
            } else {
                throw ImportFailure.invalidFile
            }
        case "tcx":
            decoded = try parseTCX(data)
        case "zwo":
            decoded = try parseZWO(data)
        default:
            throw ImportFailure.unsupported
        }

        guard !decoded.blocks.isEmpty else { throw ImportFailure.noPlannedWorkout }
        guard decoded.blocks.count <= 256 else { throw ImportFailure.tooManySteps }
        if let selectedActivity, selectedActivity != .custom,
           selectedActivity != decoded.activity {
            // A TCX run can deliberately be imported as a walk when the
            // athlete selected Walking; the file never changes workout kind.
            if !(decoded.activity == .running && selectedActivity == .walking) {
                throw ImportFailure.incompatibleActivity
            }
        }

        let safeBlocks = try decoded.blocks.map { original -> WorkoutTemplateBlock in
            guard !original.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  original.title.count <= 160,
                  original.notes.map({ $0.count <= 1_000 }) ?? true,
                  original.durationSeconds.map({ $0.isFinite && (0...72_000).contains($0) }) ?? true,
                  original.distanceMeters.map({ $0.isFinite && (0...300_000).contains($0) }) ?? true,
                  original.targetPaceSecondsPerKilometer.map({
                      $0.isFinite && (60...3_600).contains($0)
                  }) ?? true,
                  original.targetHeartRateZone.map({ (1...5).contains($0) }) ?? true
            else { throw ImportFailure.invalidFile }
            var sanitized = original
            // File-provided foreign IDs must never silently bind a private
            // route or exercise belonging to the current account.
            sanitized.routeID = nil
            sanitized.exerciseID = nil
            sanitized.editorDragID = UUID()
            if selectedActivity == .walking, sanitized.kind == .run {
                sanitized.cardioActivity = .walking
            }
            return sanitized
        }
        let name = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Preview(
            sourceName: filename,
            title: String((name.isEmpty ? "Imported workout" : name).prefix(120)),
            activity: selectedActivity == .walking ? .walking : decoded.activity,
            blocks: safeBlocks
        )
    }

    private struct JSONWorkout: Decodable {
        let title: String
        let activity: String?
        let blocks: [WorkoutTemplateBlock]
    }

    private static func inferredActivity(_ blocks: [WorkoutTemplateBlock]) -> ATHLTHPlannedWorkoutType {
        if blocks.contains(where: { $0.kind == .exercise }) { return .strength }
        if blocks.contains(where: { $0.activityTag == "cycling" }) { return .cycling }
        if blocks.contains(where: { $0.cardioActivity == .walking }) { return .walking }
        return .running
    }

    private static func parseTCX(
        _ data: Data
    ) throws -> (title: String, activity: ATHLTHPlannedWorkoutType, blocks: [WorkoutTemplateBlock]) {
        let root = try xml(data)
        let workouts = root.descendants(named: "Workout")
        guard workouts.count == 1, let workout = workouts.first else {
            throw ImportFailure.noPlannedWorkout
        }
        let sport = workout.attribute("Sport")?.lowercased() ?? "running"
        let activity: ATHLTHPlannedWorkoutType
        switch sport {
        case "running": activity = .running
        case "biking", "cycling": activity = .cycling
        default: throw ImportFailure.incompatibleActivity
        }
        var parsed: [WorkoutTemplateBlock] = []

        func insertStep(_ node: XMLNode) throws {
            guard parsed.count < 256 else { throw ImportFailure.tooManySteps }
            let suppliedName = node.child("Name")?.value ?? ""
            let resting = node.child("Intensity")?.value.lowercased() == "resting"
            let normalizedName = suppliedName.lowercased()
            let phase: WorkoutPhaseKind =
                normalizedName.contains("warm") || normalizedName.contains("oppvarming")
                ? .warmup
                : normalizedName.contains("cool") || normalizedName.contains("nedjogg")
                  ? .cooldown
                  : resting ? .recovery : .main
            let duration = node.child("Duration")
            let seconds = duration?.child("Seconds").flatMap { Double($0.value) }
            let metres = duration?.child("Meters").flatMap { Double($0.value) }
            if let seconds, !(5...72_000).contains(seconds) {
                throw ImportFailure.invalidFile
            }
            if let metres, !(10...300_000).contains(metres) {
                throw ImportFailure.invalidFile
            }
            // The Garmin TCX "Open_t" duration deliberately stays open-ended,
            // never invent an elapsed time from a recorded workout.
            guard seconds != nil || metres != nil ||
                    duration?.attribute("type")?.lowercased().contains("open") == true
            else { throw ImportFailure.invalidFile }

            let targetNode = node.child("Target")
            let zoneValue = targetNode?.descendants(named: "HeartRateZone").first?.value
            let zone = zoneValue.flatMap(Int.init).flatMap {
                (1...5).contains($0) ? $0 : nil
            }
            let title = suppliedName.isEmpty
                ? (resting ? "Pause" : "Workout step \(parsed.count + 1)")
                : suppliedName
            var block = WorkoutTemplateBlock(
                sequence: parsed.count + 1,
                kind: activity == .cycling ? .note : (resting ? .rest : .run),
                title: title,
                exerciseSlug: nil, distanceMeters: metres,
                repetitions: nil, durationSeconds: seconds,
                targetWeightKilograms: nil, loadNote: nil,
                notes: nil, phase: phase,
                targetHeartRateZone: resting ? nil : zone
            )
            if activity == .cycling { block.activityTag = "cycling" }
            if activity == .running { block.cardioActivity = .running }
            parsed.append(block)
        }

        func expand(_ container: XMLNode, level: Int = 0) throws {
            guard level < 8 else { throw ImportFailure.invalidFile }
            for node in container.children {
                if node.name == "Step" {
                    try insertStep(node)
                } else if node.name == "Repeat" {
                    let count = Int(node.child("Repetitions")?.value ?? "") ?? 0
                    guard (1...50).contains(count) else { throw ImportFailure.invalidFile }
                    for _ in 0..<count { try expand(node, level: level + 1) }
                } else if node.name == "Steps" {
                    try expand(node, level: level + 1)
                }
            }
        }
        try expand(workout)
        guard !parsed.isEmpty else { throw ImportFailure.noPlannedWorkout }
        return (workout.child("Name")?.value ?? "Imported TCX workout", activity, parsed)
    }

    private static func parseZWO(
        _ data: Data
    ) throws -> (title: String, activity: ATHLTHPlannedWorkoutType, blocks: [WorkoutTemplateBlock]) {
        let root = try xml(data)
        guard root.name == "workout_file",
              let workout = root.child("workout") else {
            throw ImportFailure.noPlannedWorkout
        }
        var parsed: [WorkoutTemplateBlock] = []

        func append(
            _ name: String, seconds: Double, phase: WorkoutPhaseKind,
            ftpPower: Double?
        ) throws {
            guard parsed.count < 256 else { throw ImportFailure.tooManySteps }
            guard seconds.isFinite, (5...72_000).contains(seconds) else {
                throw ImportFailure.invalidFile
            }
            var block = WorkoutTemplateBlock(
                sequence: parsed.count + 1, kind: .note,
                title: name, exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: seconds,
                targetWeightKilograms: nil, loadNote: nil,
                notes: ftpPower.map { "Zwift: \(Int(($0 * 100).rounded()))% FTP" },
                phase: phase
            )
            block.activityTag = "cycling"
            parsed.append(block)
        }

        for step in workout.children {
            let label: String
            let phase: WorkoutPhaseKind
            switch step.name {
            case "Warmup": label = "Warm-up"; phase = .warmup
            case "Cooldown": label = "Cool-down"; phase = .cooldown
            case "SteadyState": label = "Steady cycling"; phase = .main
            case "FreeRide": label = "Free ride"; phase = .main
            case "Ramp": label = "Ramp"; phase = .main
            case "IntervalsT":
                let reps = Int(step.attribute("Repeat") ?? "") ?? 0
                let on = Double(step.attribute("OnDuration") ?? "") ?? 0
                let off = Double(step.attribute("OffDuration") ?? "") ?? 0
                guard (1...50).contains(reps), parsed.count + reps * 2 <= 256
                else { throw ImportFailure.tooManySteps }
                for index in 1...reps {
                    try append("Effort \(index)/\(reps)", seconds: on, phase: .main,
                               ftpPower: Double(step.attribute("OnPower") ?? ""))
                    try append("Recovery \(index)/\(reps)", seconds: off, phase: .recovery,
                               ftpPower: Double(step.attribute("OffPower") ?? ""))
                }
                continue
            default:
                // Skip metadata, not entire supported workout data.
                continue
            }
            let time = Double(step.attribute("Duration") ?? "") ?? 0
            let power = Double(step.attribute("Power") ??
                step.attribute("PowerHigh") ?? step.attribute("PowerLow") ?? "")
            try append(label, seconds: time, phase: phase, ftpPower: power)
        }
        guard !parsed.isEmpty else { throw ImportFailure.noPlannedWorkout }
        // FTP-based Zwift targets are deliberately kept as notes, not
        // transformed into HR zones or running pace.
        return (root.child("name")?.value ?? "Imported Zwift workout", .cycling, parsed)
    }

    private static func xml(_ data: Data) throws -> XMLNode {
        let reader = XMLTreeReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let root = reader.root else {
            throw ImportFailure.invalidFile
        }
        return root
    }
}

private struct XMLNode {
    let name: String
    let attributes: [String: String]
    var value: String = ""
    var children: [XMLNode] = []

    func attribute(_ key: String) -> String? {
        attributes.first {
            $0.key.split(separator: ":").last.map(String.init)?
                .caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }
    func child(_ name: String) -> XMLNode? {
        children.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    func descendants(named name: String) -> [XMLNode] {
        var found: [XMLNode] = []
        for next in children {
            if next.name.caseInsensitiveCompare(name) == .orderedSame {
                found.append(next)
            }
            found.append(contentsOf: next.descendants(named: name))
        }
        return found
    }
}

private final class XMLTreeReader: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private var nodes = 0
    var root: XMLNode?

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        nodes += 1
        guard nodes < 4_000, stack.count < 30 else {
            parser.abortParsing()
            return
        }
        let localName = elementName.split(separator: ":").last.map(String.init)
            ?? elementName
        stack.append(XMLNode(name: localName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        if stack[stack.count - 1].value.count + string.count < 5_000 {
            stack[stack.count - 1].value += string
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        guard let node = stack.popLast() else { return }
        if stack.isEmpty {
            root = XMLNode(
                name: node.name, attributes: node.attributes,
                value: node.value.trimmingCharacters(in: .whitespacesAndNewlines),
                children: node.children
            )
        } else {
            stack[stack.count - 1].children.append(XMLNode(
                name: node.name, attributes: node.attributes,
                value: node.value.trimmingCharacters(in: .whitespacesAndNewlines),
                children: node.children
            ))
        }
    }
}
