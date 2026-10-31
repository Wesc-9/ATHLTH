import SwiftUI

/// Single compact Train-style Basic layout used by Quick Train and
/// Plan > Build from scratch. Start/scheduling remains owned by the caller.
struct ATHLTHBasicRunningSetupView: View {
    @Binding var workoutName: String
    @Binding var workoutDate: Date
    @Binding var mode: RunQuickStartMode
    @Binding var environment: RunEnvironment

    var routeTitle: String? = nil
    var workoutTitle: String? = nil
    var onChooseRoute: () -> Void = {}
    var onChooseWorkout: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private var suggestedName: String {
        switch mode {
        case .free:
            switch environment {
            case .outdoor:
                return tr("Outdoor run", "Løpetur ute")
            case .indoor:
                return tr("Indoor run", "Innendørsløping")
            case .treadmill:
                return tr("Treadmill run", "Tredemølleøkt")
            }
        case .route:
            return routeTitle ?? tr("Route run", "Løping med rute")
        case .structured:
            return workoutTitle ?? tr("Running workout", "Løpeøkt")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            detailsCard
            compactPicker(
                title: tr("Run type", "Løpetype"),
                items: RunQuickStartMode.allCases.map {
                    (id: $0.rawValue, title: $0.title, symbol: $0.icon)
                },
                selection: mode.rawValue,
                onSelect: { identifier in
                    guard let next = RunQuickStartMode(rawValue: identifier) else { return }
                    if next == .route, environment != .outdoor {
                        environment = .outdoor
                    }
                    mode = next
                    if next == .route { onChooseRoute() }
                    if next == .structured { onChooseWorkout() }
                }
            )
            compactPicker(
                title: tr("Training location", "Hvor trener du?"),
                items: RunEnvironment.allCases.map {
                    (id: $0.rawValue, title: $0.title, symbol: $0.systemImage)
                },
                selection: environment.rawValue,
                onSelect: { identifier in
                    guard let next = RunEnvironment(rawValue: identifier) else { return }
                    environment = next
                    if next != .outdoor && mode == .route { mode = .free }
                }
            )
            if mode == .route, let routeTitle {
                selectionSummary(
                    title: routeTitle, symbol: "map",
                    changeTitle: tr("Change route", "Bytt rute"),
                    action: onChooseRoute
                )
            } else if mode == .structured, let workoutTitle {
                selectionSummary(
                    title: workoutTitle, symbol: "rectangle.stack",
                    changeTitle: tr("Change workout", "Bytt økt"),
                    action: onChooseWorkout
                )
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "figure.run")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("WORKOUT DETAILS", "ØKTDETALJER"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(bronze)
                    Text(tr("Running", "Løping"))
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
            }

            TextField(suggestedName, text: $workoutName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink)
                .tint(bronze)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(ATHLTHPlanDesign.canvas,
                            in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(tr("Workout name, optional", "Øktnavn, valgfritt"))
                .accessibilityHint(tr(
                    "Leave blank to use the suggested workout name.",
                    "La feltet stå tomt for å bruke navneforslaget."
                ))

            HStack(spacing: 8) {
                DatePicker(
                    tr("Date", "Dato"),
                    selection: $workoutDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(tr("Date", "Dato"))

                Rectangle()
                    .fill(ATHLTHTrainDesign.rule.opacity(0.5))
                    .frame(width: 1, height: 28)

                DatePicker(
                    tr("Time", "Tid"),
                    selection: $workoutDate,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(tr("Time", "Tid"))
            }
        }
        .padding(15)
        .athlthTrainPaper()
    }

    private func compactPicker(
        title: String,
        items: [(id: String, title: String, symbol: String)],
        selection: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            HStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let selected = item.id == selection
                    Button { onSelect(item.id) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(selected ? .white : bronze)
                                .frame(width: 36, height: 36)
                                .background(
                                    selected ? ATHLTHTrainDesign.bronze
                                             : ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 11)
                                )
                            Text(item.title)
                                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 92 : 77)
                        .padding(.horizontal, 3)
                        .background(
                            ATHLTHTrainDesign.paper,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    selected ? ATHLTHTrainDesign.gold
                                             : ATHLTHTrainDesign.rule.opacity(0.4),
                                    lineWidth: selected ? 1.3 : 0.8
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }

    private func selectionSummary(
        title: String, symbol: String, changeTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(bronze)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(ink)
                Spacer(minLength: 8)
                Text(changeTitle).font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(bronze)
            }
            .padding(12)
            .athlthPlanCard(radius: 13)
        }
        .buttonStyle(.plain)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}
