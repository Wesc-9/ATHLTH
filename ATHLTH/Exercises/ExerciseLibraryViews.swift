import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct ExerciseLibraryView: View {
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    let selectionTitle: String?
    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var query = ""
    @State private var selectedBodyPart = "All"
    @State private var selectedEquipment = "All"
    @State private var showingCreateExercise = false

    init(
        selectionTitle: String? = nil,
        onSelect: ((ExerciseLibraryEntry) -> Void)? = nil
    ) {
        self.selectionTitle = selectionTitle
        self.onSelect = onSelect
    }

    private var results: [ExerciseLibraryEntry] {
        library.search(
            query: query,
            bodyPart: selectedBodyPart,
            equipment: selectedEquipment
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            filters

            if library.isLoading && library.repDBExercises.isEmpty {
                ProgressView("Loading exercise library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No exercises" : "No matches",
                    systemImage: "dumbbell",
                    description: Text(
                        library.errorMessage ??
                        "Try another search or create your own exercise."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { entry in
                            NavigationLink {
                                ExerciseDetailView(
                                    entry: entry,
                                    selectionTitle: selectionTitle,
                                    onSelect: onSelect
                                )
                            } label: {
                                exerciseRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(selectionTitle ?? "Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateExercise = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateExercise) {
            CustomExerciseEditorView()
                .environmentObject(library)
                .environmentObject(session)
        }
        .task {
            await library.refresh()
        }
        .refreshable {
            await library.refresh(force: true)
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search exercise, muscle or equipment", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(11)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("All") { selectedBodyPart = "All" }
                        ForEach(library.bodyParts, id: \.self) { part in
                            Button(part) { selectedBodyPart = part }
                        }
                    } label: {
                        filterChip(
                            selectedBodyPart == "All"
                                ? "Muscle group"
                                : selectedBodyPart,
                            active: selectedBodyPart != "All"
                        )
                    }

                    Menu {
                        Button("All") { selectedEquipment = "All" }
                        ForEach(library.equipmentOptions, id: \.self) { equipment in
                            Button(equipment) { selectedEquipment = equipment }
                        }
                    } label: {
                        filterChip(
                            selectedEquipment == "All"
                                ? "Equipment"
                                : selectedEquipment,
                            active: selectedEquipment != "All"
                        )
                    }

                    if selectedBodyPart != "All" || selectedEquipment != "All" {
                        Button("Clear") {
                            selectedBodyPart = "All"
                            selectedEquipment = "All"
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func filterChip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(active ? .white : .primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            active ? ATHLTHTheme.accent : Color(.secondarySystemGroupedBackground),
            in: Capsule()
        )
    }

    private func exerciseRow(_ entry: ExerciseLibraryEntry) -> some View {
        HStack(spacing: 13) {
            ExerciseArtwork(entry: entry, size: 68)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if entry.source == .custom {
                        Text("CUSTOM")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(ATHLTHTheme.accent.opacity(0.10), in: Capsule())
                    }
                }

                Text(
                    [
                        entry.bodyPart,
                        entry.exercise.equipment.first
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let difficulty = entry.difficulty {
                    Text(difficulty)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }
}

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore

    let entry: ExerciseLibraryEntry
    let selectionTitle: String?
    let onSelect: ((ExerciseLibraryEntry) -> Void)?

    @State private var showingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artwork

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name)
                        .font(.largeTitle.bold())

                    Text(
                        [
                            entry.bodyPart,
                            entry.difficulty,
                            entry.exercise.equipment.first
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                }

                if !entry.exercise.primaryMuscles.isEmpty ||
                    !entry.exercise.secondaryMuscles.isEmpty {
                    detailCard("Muscles") {
                        if !entry.exercise.primaryMuscles.isEmpty {
                            LabeledContent(
                                "Primary",
                                value: entry.exercise.primaryMuscles.joined(separator: ", ")
                            )
                        }

                        if !entry.exercise.secondaryMuscles.isEmpty {
                            LabeledContent(
                                "Secondary",
                                value: entry.exercise.secondaryMuscles.joined(separator: ", ")
                            )
                        }
                    }
                }

                if !entry.exercise.instructions.isEmpty {
                    detailCard("How to perform") {
                        ForEach(
                            Array(entry.exercise.instructions.enumerated()),
                            id: \.offset
                        ) { index, instruction in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 24, height: 24)
                                    .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

                                Text(instruction)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                if let videoURL = entry.exercise.videoURL {
                    detailCard("Video") {
                        VideoPlayer(
                            player: AVPlayer(url: videoURL)
                        )
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        Link(destination: videoURL) {
                            Label("Open source video", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                if !entry.tips.isEmpty {
                    detailCard("Tips") {
                        ForEach(entry.tips, id: \.self) { tip in
                            Label(tip, systemImage: "lightbulb.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if entry.source == .repDB {
                    Link(destination: URL(string: "https://repdb.co")!) {
                        Label("Exercise data by RepDB", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                }

                if let onSelect {
                    Button {
                        onSelect(entry)
                        dismiss()
                    } label: {
                        Label(
                            selectionTitle ?? "Add Exercise",
                            systemImage: "plus.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                }

                if entry.source == .custom {
                    Button("Delete Custom Exercise", role: .destructive) {
                        showingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this custom exercise?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.deleteCustomExercise(entry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var artwork: some View {
        HStack(spacing: 10) {
            ExerciseArtwork(entry: entry, size: 160)

            if entry.imagePeakURL != nil &&
               entry.imagePeakURL != entry.imageStartURL {
                AsyncImage(url: entry.imagePeakURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        Color(.secondarySystemGroupedBackground)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private func detailCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

struct CustomExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var name = ""
    @State private var primaryMuscles = ""
    @State private var secondaryMuscles = ""
    @State private var equipment = ""
    @State private var instructions = ""
    @State private var shareable = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var videoURLText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    TextField(
                        "Primary muscles, comma separated",
                        text: $primaryMuscles
                    )
                    TextField(
                        "Secondary muscles, comma separated",
                        text: $secondaryMuscles
                    )
                    TextField(
                        "Equipment, comma separated",
                        text: $equipment
                    )
                }

                Section("Instructions") {
                    TextField(
                        "One instruction per line",
                        text: $instructions,
                        axis: .vertical
                    )
                    .lineLimit(5...12)
                }

                Section("Media") {
                    if let selectedImageData,
                       let image = UIImage(data: selectedImageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            selectedImageData == nil
                                ? "Add Exercise Image"
                                : "Change Exercise Image",
                            systemImage: "photo.badge.plus"
                        )
                    }

                    TextField(
                        "Direct video URL (optional)",
                        text: $videoURLText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    Text(
                        "Your image is stored locally in ATHLTH. A direct video URL can be attached to the exercise and shown on its detail page."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Sharing") {
                    Toggle(
                        "Allow this exercise in shared plans",
                        isOn: $shareable
                    )

                    Text(
                        shareable
                            ? "The exercise snapshot can travel with a plan you share."
                            : "This custom exercise stays private to your library."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = library.createCustomExercise(
                            ownerID: session.profile.userID,
                            name: name,
                            instructions: splitLines(instructions),
                            primaryMuscles: splitCSV(primaryMuscles),
                            secondaryMuscles: splitCSV(secondaryMuscles),
                            equipment: splitCSV(equipment),
                            isVisibleOutsideOwnerLibrary: shareable,
                            imageData: selectedImageData,
                            videoURL: cleanVideoURL
                        )
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else {
                    selectedImageData = nil
                    return
                }

                Task {
                    selectedImageData = try? await item.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private var cleanVideoURL: URL? {
        let clean = videoURLText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else { return nil }
        return URL(string: clean)
    }

    private func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ExerciseArtwork: View {
    let entry: ExerciseLibraryEntry
    let size: CGFloat

    var body: some View {
        Group {
            if let url = entry.imageStartURL {
                if url.isFileURL,
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallback
                        }
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: min(size * 0.18, 20)))
    }

    private var fallback: some View {
        ATHLTHTheme.accent.opacity(0.08)
            .overlay {
                Image(
                    systemName: entry.source == .custom
                        ? "person.crop.circle.badge.plus"
                        : "dumbbell.fill"
                )
                .font(.system(size: size * 0.28))
                .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}
