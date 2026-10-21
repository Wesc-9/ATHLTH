import PhotosUI
import Supabase
import SwiftUI
import UIKit

private struct ATHLTHEquipmentScanCandidate: Encodable {
    let id: String
    let name: String
    let equipment: [String]
    let primaryMuscles: [String]

    init(_ entry: ExerciseLibraryEntry) {
        id = entry.id.uuidString
        name = entry.name
        equipment = entry.exercise.equipment
        primaryMuscles = entry.exercise.primaryMuscles
    }
}

private struct ATHLTHEquipmentScanRequest: Encodable {
    let imageBase64: String
    let language: String
    let candidates: [ATHLTHEquipmentScanCandidate]
}

/// Balanced, deterministic shortlist for the vision API's bounded context.
/// Without this, the first 100 alphabetically sorted exercises can all be
/// from a small set of movement names and miss the scanned equipment.
enum ATHLTHEquipmentScanCandidateSelector {
    static func select(
        from exercises: [ExerciseLibraryEntry],
        limit: Int = 100
    ) -> [ExerciseLibraryEntry] {
        guard limit > 0 else { return [] }
        let ordered = exercises
            .filter { $0.source != .custom }
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }

        var groups: [String: [ExerciseLibraryEntry]] = [:]
        for exercise in ordered {
            let equipment = exercise.exercise.equipment.first?
                .lowercased() ?? "other"
            let muscle = exercise.bodyPart?.lowercased()
                ?? exercise.exercise.primaryMuscles.first?.lowercased()
                ?? "other"
            groups[equipment + ":" + muscle, default: []].append(exercise)
        }

        let keys = groups.keys.sorted()
        var indices = Dictionary(uniqueKeysWithValues:
            keys.map { ($0, 0) })
        var result: [ExerciseLibraryEntry] = []
        result.reserveCapacity(min(ordered.count, limit))
        while result.count < limit {
            var advanced = false
            for key in keys {
                let index = indices[key, default: 0]
                guard let group = groups[key],
                      group.indices.contains(index) else { continue }
                result.append(group[index])
                indices[key] = index + 1
                advanced = true
                if result.count == limit { break }
            }
            if !advanced { break }
        }
        return result
    }
}

struct ATHLTHEquipmentScanResponse: Decodable {
    let equipmentName: String
    let confidence: String
    let explanation: String
    let exerciseIDs: [String]

    /// Reject uncertain, unknown and duplicate IDs even if an AI response is malformed.
    func matchedExercises(in candidates: [ExerciseLibraryEntry]) -> [ExerciseLibraryEntry] {
        guard confidence == "high" || confidence == "medium" else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id.uuidString, $0) })
        var seen = Set<String>()
        return exerciseIDs.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
    }
}

enum ATHLTHEquipmentScannerError: LocalizedError, Equatable {
    case invalidPhoto
    case imageTooLarge
    case providerPayloadTooLarge
    case signInRequired
    case premiumRequired
    case rateLimited
    case temporarilyUnavailable
    case timedOut
    case connectionFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidPhoto:
            return ATHLTHLocalization.choose(
                english: "Could not read the image. Take another photo.",
                norwegian: "Kunne ikke lese bildet. Ta et nytt bilde."
            )
        case .imageTooLarge:
            return ATHLTHLocalization.choose(
                english: "The image could not be reduced enough. Try a simpler photo.",
                norwegian: "Bildet kunne ikke gjøres lite nok. Prøv et enklere bilde."
            )
        case .providerPayloadTooLarge:
            return ATHLTHLocalization.choose(
                english: "The image service rejected the photo size. Try another photo.",
                norwegian: "Bildet ble avvist fordi filen er for stor. Prøv et nytt bilde."
            )
        case .signInRequired:
            return ATHLTHLocalization.choose(
                english: "Your session has expired. Sign in again to scan equipment.",
                norwegian: "Innloggingen har utløpt. Logg inn på nytt for å skanne."
            )
        case .premiumRequired:
            return ATHLTHLocalization.choose(
                english: "The scanner requires an active ATHLTH+ subscription.",
                norwegian: "Skanneren krever et aktivt ATHLTH+-abonnement."
            )
        case .rateLimited:
            return ATHLTHLocalization.choose(
                english: "The AI service is busy or you reached the scan limit. Try later.",
                norwegian: "AI-tjenesten er opptatt eller skannegrensen er nådd. Prøv senere."
            )
        case .temporarilyUnavailable:
            return ATHLTHLocalization.choose(
                english: "Image analysis is temporarily unavailable. Try again later.",
                norwegian: "Bildeanalysen er midlertidig utilgjengelig. Prøv igjen senere."
            )
        case .timedOut:
            return ATHLTHLocalization.choose(
                english: "The analysis took too long. Try again.",
                norwegian: "Analysen tok for lang tid. Prøv igjen."
            )
        case .connectionFailed:
            return ATHLTHLocalization.choose(
                english: "Could not connect to the image service. Check your internet connection.",
                norwegian: "Kunne ikke koble til bildetjenesten. Sjekk internettforbindelsen."
            )
        case .invalidResponse:
            return ATHLTHLocalization.choose(
                english: "The image service sent an unreadable answer. Try again.",
                norwegian: "Bildetjenesten ga et ugyldig svar. Prøv igjen."
            )
        }
    }

    private struct ServiceFailure: Decodable {
        let code: String?
    }

    static func from(_ error: Error) -> ATHLTHEquipmentScannerError {
        if let known = error as? ATHLTHEquipmentScannerError { return known }
        if let service = error as? FunctionsError {
            switch service {
            case .relayError:
                return .connectionFailed
            case let .httpError(status, data):
                let code = (try? JSONDecoder().decode(ServiceFailure.self, from: data))?.code
                switch code {
                case "VISION_PAYLOAD_TOO_LARGE": return .providerPayloadTooLarge
                case "VISION_TIMEOUT": return .timedOut
                case "VISION_NETWORK_ERROR": return .connectionFailed
                case "VISION_RATE_LIMIT", "AI_RATE_LIMIT": return .rateLimited
                case "PREMIUM_REQUIRED": return .premiumRequired
                case "VISION_INVALID_RESPONSE": return .invalidResponse
                default: break
                }
                switch status {
                case 401: return .signInRequired
                case 403: return .premiumRequired
                case 413: return .providerPayloadTooLarge
                case 429: return .rateLimited
                case 504: return .timedOut
                default: return .temporarilyUnavailable
                }
            }
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .timedOut : .connectionFailed
        }
        if error is DecodingError { return .invalidResponse }
        return .temporarilyUnavailable
    }
}

/// Generate a bounded JPEG with exactly 1 pixel per renderer point.
/// The old default UIGraphicsImageRenderer used the iPhone's 3x display
/// scale, silently increasing a nominally 1000px photo to 3000px and
/// generating requests that Groq rejects with HTTP 413.
@MainActor
enum ATHLTHEquipmentPhotoEncoder {
    static let maximumJPEGBytes = 240_000

    static func jpegData(for image: UIImage) throws -> Data {
        let original = image.size
        guard original.width.isFinite, original.height.isFinite,
              original.width > 0, original.height > 0 else {
            throw ATHLTHEquipmentScannerError.invalidPhoto
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let options: [(side: CGFloat, quality: CGFloat)] = [
            (800, 0.60), (680, 0.48), (540, 0.40)
        ]
        for option in options {
            let factor = min(1, option.side / max(original.width, original.height))
            let dimensions = CGSize(
                width: max(1, (original.width * factor).rounded()),
                height: max(1, (original.height * factor).rounded())
            )
            let renderer = UIGraphicsImageRenderer(size: dimensions, format: format)
            let rendered = renderer.image { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: dimensions))
                image.draw(in: CGRect(origin: .zero, size: dimensions))
            }
            if let data = rendered.jpegData(compressionQuality: option.quality),
               !data.isEmpty, data.count <= maximumJPEGBytes {
                return data
            }
        }
        throw ATHLTHEquipmentScannerError.imageTooLarge
    }
}

@MainActor
final class ATHLTHEquipmentVisionService {
    private let client = SupabaseEnvironment.client

    func analyze(
        image: UIImage,
        exercises: [ExerciseLibraryEntry]
    ) async throws -> ATHLTHEquipmentScanResponse {
        let data = try ATHLTHEquipmentPhotoEncoder.jpegData(for: image)
        do {
            return try await client.functions.invoke(
                "identify-gym-equipment",
                options: FunctionInvokeOptions(
                    body: ATHLTHEquipmentScanRequest(
                        imageBase64: data.base64EncodedString(),
                        language: ATHLTHLocalization.isNorwegian ? "no" : "en",
                        candidates: exercises.prefix(100).map(ATHLTHEquipmentScanCandidate.init)
                    )
                )
            )
        } catch {
            throw ATHLTHEquipmentScannerError.from(error)
        }
    }
}

/// Camera stills only. Users actively capture one photo and explicitly choose
/// whether to send it to ATHLTH AI. No continuous camera stream is uploaded.
struct ATHLTHEquipmentCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

/// Reuses the authoritative ATHLTH exercise catalogue; results never create
/// fabricated exercise IDs or modify a workout until the user selects one.
struct ATHLTHEquipmentScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore

    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var isCameraOpen = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isAnalyzing = false
    @State private var analysis: ATHLTHEquipmentScanResponse?
    @State private var message: String?

    private let scanner = ATHLTHEquipmentVisionService()

    init(onSelect: ((ExerciseLibraryEntry) -> Void)? = nil) {
        self.onSelect = onSelect
    }

    private var candidates: [ExerciseLibraryEntry] {
        ATHLTHEquipmentScanCandidateSelector.select(
            from: library.search(query: "")
        )
    }

    private var matches: [ExerciseLibraryEntry] {
        analysis?.matchedExercises(in: candidates) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ATHLTHPlanSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("ATHLTH VISION")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.7)
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                                Spacer()
                                Image(systemName: "camera.viewfinder")
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "What can I train here?",
                                norwegian: "Hva kan jeg trene her?"
                            ))
                            .font(.system(size: 27, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "Photograph a gym machine. ATHLTH suggests suitable exercises from the exercise library.",
                                norwegian: "Ta bilde av et treningsapparat. ATHLTH foreslår øvelser fra vårt eget bibliotek."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }

                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Selected equipment photo",
                                norwegian: "Valgt bilde av treningsapparat"
                            ))
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(ATHLTHPlanDesign.selectedSurface)
                            .frame(height: 170)
                            .overlay {
                                VStack(spacing: 9) {
                                    Image(systemName: "camera.metering.center.weighted")
                                        .font(.system(size: 32, weight: .light))
                                    Text(ATHLTHLocalization.choose(
                                        english: "Photograph the entire machine",
                                        norwegian: "Ta bilde av hele apparatet"
                                    ))
                                    .font(.subheadline)
                                }
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                    }

                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                isCameraOpen = true
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Open camera", norwegian: "Åpne kamera"
                                ), systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHPlanDesign.ink)
                        }

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(ATHLTHLocalization.choose(
                                english: "Choose photo", norwegian: "Velg bilde"
                            ), systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHPlanDesign.ink)
                    }

                    if photo != nil {
                        Button {
                            Task { await analyzePhoto() }
                        } label: {
                            HStack(spacing: 8) {
                                if isAnalyzing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(ATHLTHLocalization.choose(
                                    english: "Find exercises with AI",
                                    norwegian: "Finn øvelser med AI"
                                ))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(ATHLTHPlanDesign.ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAnalyzing)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Nothing is uploaded until you tap Find exercises. The resized photo is sent to the AI provider for analysis, but ATHLTH does not store it on its server. Recognition can be wrong; verify the machine instructions.",
                        norwegian: "Ingenting sendes før du trykker Finn øvelser. Et nedskalert bilde sendes til AI-leverandøren for analyse, men ATHLTH lagrer det ikke på serveren. Gjenkjenningen kan ta feil – kontroller instruksjonene på apparatet."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    if let message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    if let analysis {
                        ATHLTHPlanSurface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Equipment analysis",
                                    norwegian: "Analyse av apparatet"
                                ))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                Text(analysis.equipmentName)
                                    .font(.system(size: 24, design: .serif))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(analysis.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                Text(confidenceLabel(for: analysis.confidence))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        analysis.confidence == "high" ? ATHLTHPlanDesign.ink : Color.orange
                                    )
                            }
                        }

                        if matches.isEmpty {
                            ContentUnavailableView {
                                Label(ATHLTHLocalization.choose(
                                    english: "No reliable exercise match",
                                    norwegian: "Ingen sikre øvelsesforslag"
                                ), systemImage: "questionmark.circle")
                            } description: {
                                Text(ATHLTHLocalization.choose(
                                    english: "Try a clearer photo of the full machine, including handles and weights.",
                                    norwegian: "Prøv et tydeligere bilde av hele apparatet, inkludert håndtak og vekter."
                                ))
                            }
                        } else {
                            Text(ATHLTHLocalization.choose(
                                english: "Suggested exercises",
                                norwegian: "Foreslåtte øvelser"
                            ))
                            .font(.system(size: 23, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                            ForEach(matches) { entry in
                                Group {
                                    if let onSelect {
                                        Button {
                                            onSelect(entry)
                                            dismiss()
                                        } label: {
                                            exerciseRow(entry)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink {
                                            ExerciseDetailView(
                                                entry: entry,
                                                selectionTitle: nil,
                                                onSelect: nil
                                            )
                                        } label: {
                                            exerciseRow(entry)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Equipment scanner", norwegian: "Apparatskanner"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $isCameraOpen) {
                ATHLTHEquipmentCameraPicker(
                    onCapture: { captured in
                        photo = captured
                        analysis = nil
                        message = nil
                        isCameraOpen = false
                    },
                    onCancel: { isCameraOpen = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                Task {
                    do {
                        guard let data = try await selection.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            throw ATHLTHEquipmentScannerError.invalidPhoto
                        }
                        photo = image
                        analysis = nil
                        message = nil
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        }
    }

    private func exerciseRow(_ entry: ExerciseLibraryEntry) -> some View {
        ATHLTHPlanSurface {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 17))
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.localizedExerciseName(entry))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(entry.exercise.primaryMuscles.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer()
                Image(systemName: onSelect == nil ? "chevron.right" : "plus.circle.fill")
                    .foregroundStyle(ATHLTHPlanDesign.accent)
            }
        }
    }

    private func confidenceLabel(for value: String) -> String {
        switch value {
        case "high":
            return ATHLTHLocalization.choose(
                english: "Likely equipment match",
                norwegian: "Sannsynlig apparatmatch"
            )
        case "medium":
            return ATHLTHLocalization.choose(
                english: "Possible match – verify the machine",
                norwegian: "Mulig match – kontroller apparatet"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Uncertain identification",
                norwegian: "Usikker gjenkjenning"
            )
        }
    }

    private func analyzePhoto() async {
        guard let photo, !isAnalyzing else { return }
        isAnalyzing = true
        analysis = nil
        message = nil
        defer { isAnalyzing = false }
        do {
            analysis = try await scanner.analyze(image: photo, exercises: candidates)
        } catch {
            message = ATHLTHLocalization.choose(
                english: "ATHLTH AI could not analyze the photo. ",
                norwegian: "ATHLTH AI klarte ikke å analysere bildet. "
            ) + error.localizedDescription
        }
    }
}
