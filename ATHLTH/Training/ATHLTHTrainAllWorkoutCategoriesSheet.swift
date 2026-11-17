import SwiftUI

/// One small entry point for the activities supported by the existing Train
/// engine. It routes to the established recorders and workout library; it
/// never creates an independent workout recording or a second plan model.
struct ATHLTHTrainAllWorkoutCategoriesSheet: View {
    enum Action {
        case freeRun
        case runIntervals
        case freeWalk
        case freeStrength
        case strengthLibrary
        case cycling
        case freeTraining
        case custom(CustomQuickWorkoutActivity)
    }

    private enum Category: String, CaseIterable, Identifiable {
        case running, walking, strength, cycling, freeTraining, custom
        case hiit, circuit, functional, rowing, stairClimber, mobility, yoga, sports

        var id: String { rawValue }

        var title: String {
            switch self {
            case .running: return tr("Running", "Løping")
            case .walking: return tr("Walking", "Gå")
            case .strength: return tr("Strength", "Styrke")
            case .cycling: return tr("Cycling", "Sykling")
            case .freeTraining: return tr("Free training", "Fri trening")
            case .custom: return tr("Custom", "Egendefinert")
            case .hiit: return "HIIT"
            case .circuit: return tr("Circuit training", "Sirkeltrening")
            case .functional: return tr("Functional", "Funksjonell")
            case .rowing: return tr("Rowing", "Roing")
            case .stairClimber: return tr("Stairs", "Trapper")
            case .mobility: return tr("Mobility", "Mobilitet")
            case .yoga: return "Yoga"
            case .sports: return tr("Sports", "Idrett")
            }
        }

        var subtitle: String {
            switch self {
            case .running: return tr("Route, free run or intervals", "Rute, fri løping eller intervall")
            case .walking: return tr("Free walk or route", "Fri gåtur eller rute")
            case .strength: return tr("Free strength or saved sessions", "Fri styrke eller lagrede økter")
            case .cycling: return tr("Indoor or outdoor workout", "Inne eller ute")
            case .freeTraining: return tr("Start an open workout immediately", "Start en åpen økt direkte")
            case .custom: return tr("Configure your own activity", "Tilpass en egen aktivitet")
            case .hiit, .circuit, .functional, .rowing, .stairClimber, .mobility, .yoga, .sports:
                return tr("Choose workout settings", "Velg øktoppsett")
            }
        }

        var icon: String {
            switch self {
            case .running: return "figure.run"
            case .walking: return "figure.walk"
            case .strength: return "dumbbell.fill"
            case .cycling: return "bicycle"
            case .freeTraining: return "figure.cross.training"
            case .custom: return "figure.mixed.cardio"
            case .hiit: return "figure.highintensity.intervaltraining"
            case .circuit: return "arrow.triangle.2.circlepath"
            case .functional: return "figure.strengthtraining.functional"
            case .rowing: return "figure.rower"
            case .stairClimber: return "figure.stair.stepper"
            case .mobility: return "figure.flexibility"
            case .yoga: return "figure.yoga"
            case .sports: return "sportscourt"
            }
        }

        var quickCustomActivity: CustomQuickWorkoutActivity? {
            switch self {
            case .custom: return .other
            case .hiit: return .hiit
            case .circuit: return .circuit
            case .functional: return .functional
            case .rowing: return .rowing
            case .stairClimber: return .stairClimber
            case .mobility: return .mobility
            case .yoga: return .yoga
            case .sports: return .sports
            default: return nil
            }
        }

        private func tr(_ english: String, _ norwegian: String) -> String {
            ATHLTHLocalization.choose(english: english, norwegian: norwegian)
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Category?
    let onSelect: (Action) -> Void

    private let mainCategories: [Category] = [
        .running, .walking, .strength, .cycling, .freeTraining, .custom
    ]
    private let otherCategories: [Category] = [
        .hiit, .circuit, .functional, .rowing, .stairClimber, .mobility,
        .yoga, .sports
    ]

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let selectedCategory {
                        subcategories(for: selectedCategory)
                    } else {
                        header(tr("Choose an activity", "Velg aktivitet"),
                               subtitle: tr("All training types in ATHLTH",
                                            "Alle treningstyper i ATHLTH"))
                        categorySection(tr("TRAINING", "TRENING"), categories: mainCategories)
                        categorySection(tr("OTHER ACTIVITIES", "ANDRE AKTIVITETER"),
                                        categories: otherCategories)
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("All workouts", "Alle økter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedCategory != nil {
                        Button {
                            selectedCategory = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(tr("Back to categories", "Tilbake til kategorier"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
            }
        }
        .accessibilityIdentifier("athlth-train-all-workout-categories")
    }

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHTrainDesign.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categorySection(_ label: String, categories: [Category]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            ForEach(categories) { category in
                Button {
                    switch category {
                    case .running, .walking, .strength:
                        selectedCategory = category
                    case .cycling:
                        choose(.cycling)
                    case .freeTraining:
                        choose(.freeTraining)
                    default:
                        if let kind = category.quickCustomActivity {
                            choose(.custom(kind))
                        }
                    }
                } label: {
                    optionRow(icon: category.icon, title: category.title,
                              detail: category.subtitle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-all-workouts-\(category.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func subcategories(for category: Category) -> some View {
        header(category.title, subtitle: category.subtitle)
        switch category {
        case .running:
            NavigationLink {
                routePicker
            } label: {
                optionRow(icon: "map", title: tr("Route", "Rute"),
                          detail: tr("Choose a route before running", "Velg rute før løping"))
            }
            .buttonStyle(.plain)
            actionRow(icon: "figure.run", title: tr("Free run", "Fri løping"),
                      detail: tr("Run without a planned route", "Løp uten planlagt rute"),
                      action: .freeRun)
            actionRow(icon: "timer", title: tr("Intervals", "Intervall"),
                      detail: tr("Build intervals and recovery", "Lag drag og pauser"),
                      action: .runIntervals)
        case .walking:
            actionRow(icon: "figure.walk", title: tr("Free walk", "Fri gåtur"),
                      detail: tr("Walk without a route", "Gå uten valgt rute"),
                      action: .freeWalk)
            NavigationLink {
                routePicker
            } label: {
                optionRow(icon: "map", title: tr("Route", "Rute"),
                          detail: tr("Browse walking routes", "Velg en turrute"))
            }
            .buttonStyle(.plain)
        case .strength:
            actionRow(icon: "dumbbell.fill",
                      title: tr("Free strength", "Fri styrketrening"),
                      detail: tr("Set up an open strength workout",
                                 "Start med frie styrkeøvelser"),
                      action: .freeStrength)
            actionRow(icon: "square.grid.2x2", title: tr("Saved workouts", "Lagrede økter"),
                      detail: tr("Browse your workout library", "Se treningsbiblioteket"),
                      action: .strengthLibrary)
        default:
            EmptyView()
        }
    }

    private var routePicker: some View {
        RouteLibraryListView(source: .database)
            .navigationTitle(tr("Routes", "Ruter"))
            .navigationBarTitleDisplayMode(.inline)
    }

    private func actionRow(icon: String, title: String,
                           detail: String, action: Action) -> some View {
        Button { choose(action) } label: {
            optionRow(icon: icon, title: title, detail: detail)
        }
        .buttonStyle(.plain)
    }

    private func optionRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 44, height: 44)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.48),
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19))
    }

    private func choose(_ action: Action) {
        dismiss()
        onSelect(action)
    }
}
