import SwiftUI

/// Offline-first recovery and wellness library. Uses the same authored
/// guide catalogue as Workout Studio and the advanced plan builder.
struct ATHLTHRecoveryWellnessLibraryView: View {
    var onAdd: ((ATHLTHWellnessGuide) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var focus = "all"
    @State private var displayMode: ATHLTHLibraryDisplayMode = .list
    @State private var activeGuide: ATHLTHWellnessGuide?
    @State private var showingRecoveryPlanner = false

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze
    private let paper = ATHLTHTrainDesign.paper

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private let groups = ["all", "upper", "back", "hips", "legs", "calm"]

    private func title(for key: String) -> String {
        switch key {
        case "upper": return tr("Upper body", "Overkropp")
        case "back": return tr("Back", "Rygg")
        case "hips": return tr("Hips & glutes", "Hofte og sete")
        case "legs": return tr("Legs", "Bein")
        case "calm": return tr("Breathing & calm", "Pust og ro")
        default: return tr("All", "Alle")
        }
    }

    private var visibleGuides: [ATHLTHWellnessGuide] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ATHLTHWellnessGuide.all
            .filter { guide in
                (focus == "all" || guide.focusKey == focus) &&
                (search.isEmpty || guide.titleNO.localizedCaseInsensitiveContains(search) ||
                 guide.titleEN.localizedCaseInsensitiveContains(search) ||
                 guide.detailNO.localizedCaseInsensitiveContains(search) ||
                 guide.detailEN.localizedCaseInsensitiveContains(search) ||
                 guide.focusTitle.localizedCaseInsensitiveContains(search))
            }
            .sorted {
                $0.title.compare(
                    $1.title,
                    options: [.caseInsensitive, .numeric],
                    locale: ATHLTHExerciseAlphabet.locale
                ) == .orderedAscending
            }
    }

    private var columns: [GridItem] {
        if displayMode == .grid && !dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: 164, maximum: 340), spacing: 10)]
        }
        return [GridItem(.flexible(), spacing: 9)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("RECOVERY LIBRARY", "RESTITUSJONSBIBLIOTEK"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.7)
                        .foregroundStyle(bronze)
                    Text(tr("Recovery & wellness", "Restitusjon og velvære"))
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Gentle stretching, mobility and breathing sessions. Choose a movement and start its timer immediately.",
                        "Tøying, bevegelighet og pusteøvelser samlet på ett sted. Velg en øvelse og start tiden direkte."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingRecoveryPlanner = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(bronze)
                        Text(tr("Plan a recovery day", "Planlegg en hviledag"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(paper, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    TextField(tr("Find an exercise or muscle", "Søk etter øvelse eller muskel"),
                              text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("Clear search", "Tøm søk"))
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(groups, id: \.self) { key in
                            Button {
                                focus = key
                            } label: {
                                Text(title(for: key))
                                    .font(.caption.weight(focus == key ? .semibold : .medium))
                                    .foregroundStyle(focus == key ? .white : ink)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(focus == key ? ink : Color.white,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(focus == key ? .isSelected : [])
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("\(visibleGuides.count) " + tr("exercises", "øvelser"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    Spacer()
                    ATHLTHLibraryDisplayPicker(selection: $displayMode)
                }

                if visibleGuides.isEmpty {
                    ContentUnavailableView(
                        tr("No matching movements", "Ingen treff"),
                        systemImage: "figure.flexibility",
                        description: Text(tr("Try another name or muscle group.",
                                              "Prøv et annet navn eller en annen muskelgruppe."))
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(visibleGuides) { guide in
                            guideCard(guide)
                        }
                    }
                }

                Text(tr(
                    "Move gently. Stop when you feel pain, dizziness or discomfort. This is not a rehabilitation prescription.",
                    "Beveg deg rolig. Stopp ved smerte, svimmelhet eller ubehag. Øvelsene er ikke en individuell rehabiliteringsplan."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .padding(.top, 5)
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .navigationTitle(tr("Recovery & wellness", "Restitusjon og velvære"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk"), action: onClose)
                }
            }
        }
        .sheet(isPresented: $showingRecoveryPlanner) {
            // Preserve the existing rest-day planner as an optional tool;
            // this library now provides the primary content.
            ATHLTHRecoveryRestPlanningSheet()
                .presentationDetents([.large])
        }
        .sheet(item: $activeGuide) { guide in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: guide.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(bronze)
                                .frame(width: 51, height: 51)
                                .background(paper, in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(guide.title)
                                    .font(.headline)
                                    .foregroundStyle(ink)
                                Text(guide.focusTitle)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                            }
                        }
                        ATHLTHWellnessGuideTimer(guide: guide, autoStart: true)
                    }
                    .padding(18)
                }
                .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
                .navigationTitle(tr("Active exercise", "Aktiv øvelse"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done", "Ferdig")) { activeGuide = nil }
                    }
                }
            }
        }
    }

    private func guideCard(_ guide: ATHLTHWellnessGuide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: guide.icon)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(bronze)
                    .frame(width: 46, height: 46)
                    .background(paper, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(guide.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                    Text(guide.focusTitle + " · " + guide.durationText)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(guide.instructions)
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .lineLimit(displayMode == .grid ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button {
                    activeGuide = guide
                } label: {
                    Label(tr("Start", "Start"), systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(ink, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if let onAdd {
                    Button {
                        onAdd(guide)
                    } label: {
                        Label(tr("Add", "Legg til"), systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bronze)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(paper, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(ATHLTHTheme.premiumGold.opacity(0.16), lineWidth: 0.7)
        }
    }
}
