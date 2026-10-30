import SwiftUI

/// A single grid of images for both entry routes, so the design and
/// per-account adaptive order cannot drift between planned and scratch.
enum ATHLTHWorkoutTypePickerPurpose {
    case useExisting, createFromScratch
}

struct ATHLTHPlannedWorkoutTypePickerView: View {
    let purpose: ATHLTHWorkoutTypePickerPurpose
    let onCreateNew: ((ATHLTHPlannedWorkoutType) -> Void)?
    let onSelect: (PlannedSession, ATHLTHPlannedWorkoutType) -> Void

    init(
        purpose: ATHLTHWorkoutTypePickerPurpose = .useExisting,
        onCreateNew: ((ATHLTHPlannedWorkoutType) -> Void)? = nil,
        onSelect: @escaping (PlannedSession, ATHLTHPlannedWorkoutType) -> Void
    ) {
        self.purpose = purpose
        self.onCreateNew = onCreateNew
        self.onSelect = onSelect
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkouts: StrengthWorkoutStore
    @State private var path: [ATHLTHPlannedWorkoutType] = []
    @State private var orderedTypes = ATHLTHPlannedWorkoutType.defaultOrder

    private let ink = Color(red: 0.075, green: 0.10, blue: 0.17)
    private let muted = Color(red: 0.47, green: 0.50, blue: 0.58)
    private let canvas = Color(red: 0.988, green: 0.984, blue: 0.973)

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { viewport in
                // Six categories fit in three rows on a regular iPhone.
                // Short windows and larger accessibility text can still scroll.
                let compact = viewport.size.width < 620 || viewport.size.height < 660
                let columns = Array(
                    repeating: GridItem(.flexible(minimum: 110), spacing: compact ? 10 : 12),
                    count: compact ? 2 : 3
                )
                let tileHeight = cardHeight(
                    availableHeight: viewport.size.height,
                    compact: compact
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                        header(compact: compact)

                        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
                            Text("ATHLTH · PLAN")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(3.0)
                                .foregroundStyle(ATHLTHTheme.accentDeep)

                            Text(ATHLTHLocalization.choose(
                                english: "What would you like to plan?",
                                norwegian: "Hva vil du planlegge?"
                            ))
                            .font(typeSize.isAccessibilitySize
                                  ? .title2.bold()
                                  : .system(size: compact ? 25 : 30, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(ink)

                            Text(ATHLTHLocalization.choose(
                                english: purpose == .createFromScratch
                                    ? "Choose an activity and build your own workout in the shared editor."
                                    : "Choose an activity to find and adapt an existing workout.",
                                norwegian: purpose == .createFromScratch
                                    ? "Velg aktivitet og bygg din egen økt i den felles øktbyggeren."
                                    : "Velg aktivitet for å hente og tilpasse en planlagt økt."
                            ))
                            .font(compact ? .footnote : .subheadline)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 3)

                        LazyVGrid(columns: columns, spacing: compact ? 10 : 12) {
                            ForEach(orderedTypes) { type in
                                activityTile(type, height: tileHeight, compact: compact)
                            }
                        }

                        // The tip is supplementary. Keep the six workout
                        // choices visible first on the smaller phone sheet.
                        if !compact {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "lightbulb")
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                Text(ATHLTHLocalization.choose(
                                    english: purpose == .createFromScratch
                                        ? "Start with a blank workout. Add exercises, intervals and rests using the same editor for every activity."
                                        : "Tip: You can change exercises, structure and details in the next step.",
                                    norwegian: purpose == .createFromScratch
                                        ? "Start med en tom økt. Legg til øvelser, intervaller og pauser i samme øktbygger."
                                        : "Tips: Du kan endre øvelser, struktur og detaljer i neste steg."
                                ))
                                .font(.caption)
                                .foregroundStyle(muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(canvas, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(.horizontal, compact ? 16 : 20)
                    .padding(.top, compact ? 8 : 18)
                    .padding(.bottom, compact ? 12 : 34)
                    .frame(maxWidth: 740)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .background(canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ATHLTHPlannedWorkoutType.self) { type in
                WorkoutTemplateLibraryView(
                    onSelectPlanned: { workout in
                        // Opening a category isn't usage. Picking a concrete
                        // session counts, and returns to the existing editor.
                        ATHLTHPlannedWorkoutTypeUsageStore.record(
                            type, userID: session.profile.userID
                        )
                        onSelect(workout, type)
                    },
                    initialCategory: type
                )
                .navigationTitle(type.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
            }
            .task(id: session.profile.userID) {
                orderedTypes = ATHLTHPlannedWorkoutTypeUsageStore.ordered(
                    userID: session.profile.userID,
                    healthWorkouts: health.workouts,
                    strengthHistory: strengthWorkouts.workoutHistory
                )
            }
        }
        .tint(ATHLTHTheme.accentDeep)
    }

    private func cardHeight(availableHeight: CGFloat, compact: Bool) -> CGFloat {
        if typeSize.isAccessibilitySize { return compact ? 226 : 250 }
        if compact {
            // Reserve space for sheet navigation, title and grid gutters.
            return min(178, max(146, (availableHeight - 224) / 3))
        }
        return min(250, max(180, (availableHeight - 290) / 2))
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Back", norwegian: "Tilbake"
                ))
                .frame(minWidth: 73, minHeight: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)

            Spacer(minLength: 4)
            Text(ATHLTHLocalization.choose(
                english: "Choose workout type", norwegian: "Velg økttype"
            ))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: 4)
            Color.clear
                .frame(width: 90, height: 1)
                .accessibilityHidden(true)
        }
        .padding(.bottom, compact ? 4 : 18)
    }

    private func openWorkoutType(_ type: ATHLTHPlannedWorkoutType) {
        if purpose == .createFromScratch {
            onCreateNew?(type)
        } else if path.isEmpty {
            path.append(type)
        }
    }

    private func activityTile(
        _ type: ATHLTHPlannedWorkoutType,
        height: CGFloat,
        compact: Bool
    ) -> some View {
        Button {
            openWorkoutType(type)
        } label: {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Image(type.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                        .accessibilityHidden(true)

                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.96), location: 0),
                            .init(color: .white.opacity(0.91), location: 0.25),
                            .init(color: .white.opacity(0.76), location: 0.48),
                            .init(color: .white.opacity(0.14), location: 0.76),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: type.symbol)
                            .font(.system(size: compact ? 16 : 20, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(
                                width: compact ? 34 : 48,
                                height: compact ? 34 : 48
                            )
                            .background(iconColor(type), in: Circle())

                        Text(type.title)
                            .font(typeSize.isAccessibilitySize
                                  ? .headline
                                  : .system(
                                      size: compact ? 17 : 20,
                                      weight: .bold,
                                      design: .rounded
                                  ))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.top, compact ? 6 : 18)

                        Text(type.description)
                            .font(typeSize.isAccessibilitySize
                                  ? .subheadline
                                  : .system(size: compact ? 11 : 12))
                            .foregroundStyle(muted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : (compact ? 2 : 3))
                            .padding(.top, compact ? 2 : 6)

                        Spacer(minLength: compact ? 2 : 8)

                        Image(systemName: "arrow.right")
                            .font(.system(
                                size: compact ? 16 : 19, weight: .semibold
                            ))
                            .foregroundStyle(ink)
                            .frame(
                                width: compact ? 34 : 48,
                                height: compact ? 34 : 48
                            )
                            .background(.white.opacity(0.96), in: Circle())
                    }
                    .padding(compact ? 10 : 15)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .topLeading
                    )
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22))
                .overlay {
                    RoundedRectangle(cornerRadius: compact ? 18 : 22)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                }
            }
            .frame(height: height)
            .contentShape(RoundedRectangle(cornerRadius: compact ? 18 : 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.title). \(type.description)")
        .accessibilityHint(ATHLTHLocalization.choose(
            english: purpose == .createFromScratch
                ? "Open workout editor" : "Browse workouts",
            norwegian: purpose == .createFromScratch
                ? "Åpner øktbyggeren" : "Åpner øktbiblioteket"
        ))
    }

    private func iconColor(_ type: ATHLTHPlannedWorkoutType) -> Color {
        switch type {
        case .strength: return Color(red: 0.89, green: 0.92, blue: 1)
        case .running: return Color(red: 1, green: 0.89, blue: 0.87)
        case .walking: return Color(red: 0.92, green: 0.95, blue: 0.88)
        case .cycling: return Color(red: 0.88, green: 0.92, blue: 1)
        case .mobility: return Color(red: 1, green: 0.94, blue: 0.82)
        case .custom: return Color(red: 0.94, green: 0.88, blue: 1)
        }
    }
}
