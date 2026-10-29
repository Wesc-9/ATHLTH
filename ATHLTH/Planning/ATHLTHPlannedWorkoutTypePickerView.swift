import SwiftUI

/// Shown after "Bruk planlagt økt". Uses the existing unified workout
/// library/editor; it is a navigation choice, not another workout engine.
struct ATHLTHPlannedWorkoutTypePickerView: View {
    let onSelect: (PlannedSession, ATHLTHPlannedWorkoutType) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @State private var selectedType: ATHLTHPlannedWorkoutType?
    @State private var path: [ATHLTHPlannedWorkoutType] = []
    @State private var orderedTypes = ATHLTHPlannedWorkoutType.defaultOrder

    private let columns = [
        GridItem(.flexible(minimum: 125), spacing: 12),
        GridItem(.flexible(minimum: 125), spacing: 12)
    ]
    private let ink = Color(red: 0.075, green: 0.10, blue: 0.17)
    private let muted = Color(red: 0.47, green: 0.50, blue: 0.58)
    private let canvas = Color(red: 0.988, green: 0.984, blue: 0.973)

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 9) {
                        Text("ATHLTH · PLAN")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(3.0)
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(ATHLTHLocalization.choose(
                            english: "What would you like to plan?",
                            norwegian: "Hva vil du planlegge?"
                        ))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(ink)

                        Text(ATHLTHLocalization.choose(
                            english: "Choose an activity to find and adapt an existing workout.",
                            norwegian: "Velg aktivitet for å hente og tilpasse en planlagt økt."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 3)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(orderedTypes) { type in
                            activityTile(type)
                        }
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "lightbulb")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(ATHLTHLocalization.choose(
                            english: "Tip: You can change exercises, structure and details in the next step.",
                            norwegian: "Tips: Du kan endre øvelser, struktur og detaljer i neste steg."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(canvas, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 34)
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
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
                    userID: session.profile.userID
                )
            }
        }
        .tint(ATHLTHTheme.accentDeep)
    }

    private var header: some View {
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

            Button {
                if let selectedType { path.append(selectedType) }
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Next", norwegian: "Neste"
                ))
                .frame(minWidth: 73, minHeight: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(selectedType == nil)
        }
        .padding(.bottom, 32)
    }

    private func activityTile(_ type: ATHLTHPlannedWorkoutType) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
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
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(width: 48, height: 48)
                            .background(iconColor(type), in: Circle())

                        Text(type.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.top, 18)

                        Text(type.description)
                            .font(.system(size: 12))
                            .foregroundStyle(muted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)

                        Spacer(minLength: 8)

                        Image(systemName: isSelected
                              ? "checkmark"
                              : "arrow.right")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ink)
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.96), in: Circle())
                    }
                    .padding(15)
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
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? ATHLTHTheme.accentDeep
                                : Color.white.opacity(0.85),
                            lineWidth: isSelected ? 2.4 : 1
                        )
                }
            }
            .frame(height: 300)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.title). \(type.description)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
