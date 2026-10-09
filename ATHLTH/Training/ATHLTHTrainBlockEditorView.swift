import SwiftUI

/// Create or edit a multi-week training phase without changing session data.
struct ATHLTHTrainBlockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let planID: UUID
    let weekCount: Int
    let existingBlock: TrainingPlanBlock?

    @State private var title: String
    @State private var purpose: TrainingPlanBlockPurpose
    @State private var startWeek: Int
    @State private var endWeek: Int
    @State private var goal: String
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.43)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let paper = Color(red: 0.986, green: 0.978, blue: 0.964)
    private let border = Color(red: 0.88, green: 0.86, blue: 0.83)

    init(
        planID: UUID,
        weekCount: Int,
        existingBlock: TrainingPlanBlock? = nil,
        startingWeek: Int = 1
    ) {
        self.planID = planID
        self.weekCount = max(weekCount, 1)
        self.existingBlock = existingBlock
        let first = min(max(existingBlock?.startWeek ?? startingWeek, 1), max(weekCount, 1))
        _title = State(initialValue: existingBlock?.title ?? "")
        _purpose = State(initialValue: existingBlock?.purpose ?? .foundation)
        _startWeek = State(initialValue: first)
        _endWeek = State(initialValue: min(
            max(existingBlock?.endWeek ?? min(first + 3, max(weekCount, 1)), first),
            max(weekCount, 1)
        ))
        _goal = State(initialValue: existingBlock?.goal ?? "")
    }

    private var conflictingBlock: TrainingPlanBlock? {
        session.trainingPlan(withID: planID)?.trainingBlocks?.first {
            $0.id != existingBlock?.id &&
            startWeek <= $0.endWeek && endWeek >= $0.startWeek
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count <= 80 && goal.count <= 500 &&
        startWeek >= 1 && endWeek >= startWeek && endWeek <= weekCount &&
        conflictingBlock == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading

                    VStack(alignment: .leading, spacing: 12) {
                        fieldName(tr("Block name", "Navn på blokk"))
                        TextField(
                            tr("e.g. Strength foundation", "F.eks. Grunnleggende styrke"),
                            text: $title
                        )
                        .font(.subheadline)
                        .padding(14)
                        .background(paper, in: RoundedRectangle(cornerRadius: 11))

                        fieldName(tr("Training purpose", "Treningsformål"))
                        Picker(tr("Purpose", "Formål"), selection: $purpose) {
                            ForEach(TrainingPlanBlockPurpose.allCases) { kind in
                                Label(kind.title, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                        .tint(ink)

                        fieldName(tr("Weeks in this block", "Uker i blokken"))
                        HStack(spacing: 10) {
                            weekPicker(
                                tr("From", "Fra"),
                                selection: $startWeek,
                                values: Array(1...weekCount)
                            )
                            weekPicker(
                                tr("To", "Til"),
                                selection: $endWeek,
                                values: Array(startWeek...weekCount)
                            )
                        }

                        Text(tr(
                            "\(endWeek - startWeek + 1) weeks in this phase",
                            "\(endWeek - startWeek + 1) uker i denne perioden"
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                    .padding(16)
                    .blockEditorSurface(border: border)

                    VStack(alignment: .leading, spacing: 11) {
                        fieldName(tr("What is this block for?", "Hva skal du oppnå i denne blokken?"))
                        TextField(
                            tr("Optional goal or instructions",
                               "Valgfritt mål eller egne treningsnotater"),
                            text: $goal,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .font(.subheadline)
                        .padding(13)
                        .background(paper, in: RoundedRectangle(cornerRadius: 11))

                        Label(
                            tr(
                                "Blocks describe your plan. They never change loads, scheduled workouts or past results automatically.",
                                "Blokker beskriver treningsplanen. Belastning, planlagte økter og tidligere resultater endres aldri automatisk."
                            ),
                            systemImage: "checkmark.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                    .padding(16)
                    .blockEditorSurface(border: border)

                    if let conflict = conflictingBlock {
                        Label(
                            tr(
                                "Overlaps with \(conflict.title). Choose weeks that are free.",
                                "Overlapper med \(conflict.title). Velg uker som er ledige."
                            ),
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        .font(.subheadline)
                        .foregroundStyle(ink)
                        .padding(14)
                        .background(
                            Color(red: 0.98, green: 0.94, blue: 0.88),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }

                    if existingBlock != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(tr("Remove this block", "Fjern treningsblokken"),
                                  systemImage: "trash")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 650, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack {
                        Spacer()
                        Text(tr("Save training block", "Lagre treningsblokk"))
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(height: 48)
                    .padding(.horizontal, 16)
                    .background(ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white)
            }
            .navigationTitle(
                existingBlock == nil
                    ? tr("New training block", "Ny treningsblokk")
                    : tr("Edit training block", "Rediger treningsblokk")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .onChange(of: startWeek) { _, newStart in
                if endWeek < newStart { endWeek = newStart }
            }
            .confirmationDialog(
                tr("Remove this training block?", "Fjerne treningsblokken?"),
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(tr("Remove block only", "Fjern bare blokken"), role: .destructive) {
                    deleteBlock()
                }
                Button(tr("Cancel", "Avbryt"), role: .cancel) {}
            } message: {
                Text(tr(
                    "Training weeks, workouts and recorded history will be kept.",
                    "Treningsuker, økter og treningshistorikk beholdes."
                ))
            }
            .alert(tr("Could not save the block", "Kunne ikke lagre blokken"),
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { shown in if !shown { errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("THE BIGGER PICTURE", "DET STORE BILDET"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.7)
                .foregroundStyle(bronze)
            Text(tr("Give this phase a purpose.", "Gi treningsperioden et mål."))
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(tr(
                "Keep the simple weekly planner while gaining control over longer training periods.",
                "Planlegg flere uker samlet, uten å gjøre den daglige treningsplanleggingen vanskeligere."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
        }
    }

    private func weekPicker(
        _ label: String,
        selection: Binding<Int>,
        values: [Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption)
                .foregroundStyle(muted)
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { number in
                    Text(tr("Week \(number)", "Uke \(number)")).tag(number)
                }
            }
            .tint(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(paper, in: RoundedRectangle(cornerRadius: 11))
    }

    private func fieldName(_ name: String) -> some View {
        Text(name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
    }

    private func save() {
        guard canSave else { return }
        let block = TrainingPlanBlock(
            id: existingBlock?.id ?? UUID(),
            title: title,
            purpose: purpose,
            startWeek: startWeek,
            endWeek: endWeek,
            goal: goal
        )
        if session.saveTrainingPlanBlock(planID: planID, block: block) {
            dismiss()
        } else {
            errorMessage = tr(
                "The training plan may have changed or the weeks overlap another block.",
                "Treningsplanen kan ha blitt endret, eller ukene overlapper en annen blokk."
            )
        }
    }

    private func deleteBlock() {
        guard let existingBlock else { return }
        if session.removeTrainingPlanBlock(planID: planID, blockID: existingBlock.id) {
            dismiss()
        } else {
            errorMessage = tr(
                "This block could not be removed.",
                "Kunne ikke fjerne treningsblokken."
            )
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func blockEditorSurface(border: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(border, lineWidth: 0.7)
            }
    }
}
