import SwiftUI

/// A local intake. Nothing reaches Coach until the normal AI/health consent
/// flow has accepted the resulting draft.
struct ATHLTHCoachWorkoutWizardView: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: (String) -> Void

    private enum WorkoutType: String, CaseIterable, Identifiable {
        case strength, running, walking, cycling, combined
        var id: String { rawValue }
        var title: String {
            switch self {
            case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
            case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
            case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåtur")
            case .cycling: return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
            case .combined: return ATHLTHLocalization.choose(english: "Combination", norwegian: "Kombinasjon")
            }
        }
    }

    private enum Venue: String, CaseIterable, Identifiable {
        case gym, home, outdoors, mixed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gym: return ATHLTHLocalization.choose(english: "Gym", norwegian: "Treningssenter")
            case .home: return ATHLTHLocalization.choose(english: "At home", norwegian: "Hjemme")
            case .outdoors: return ATHLTHLocalization.choose(english: "Outdoors", norwegian: "Ute")
            case .mixed: return ATHLTHLocalization.choose(english: "Flexible", norwegian: "Fleksibelt")
            }
        }
    }

    private enum Level: String, CaseIterable, Identifiable {
        case beginner, regular, experienced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .beginner: return ATHLTHLocalization.choose(english: "Beginner", norwegian: "Nybegynner")
            case .regular: return ATHLTHLocalization.choose(english: "Intermediate", norwegian: "Vanlig")
            case .experienced: return ATHLTHLocalization.choose(english: "Experienced", norwegian: "Erfaren")
            }
        }
    }

    @State private var type: WorkoutType = .strength
    @State private var venue: Venue = .gym
    @State private var level: Level = .regular
    @State private var duration = 45
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Workout type", "Treningsform"), selection: $type) {
                        ForEach(WorkoutType.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(tr("Where", "Hvor"), selection: $venue) {
                        ForEach(Venue.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(tr("Experience", "Erfaring"), selection: $level) {
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(tr("Duration", "Varighet"), selection: $duration) {
                        ForEach([15, 20, 30, 40, 45, 60, 75, 90, 120], id: \.self) { value in
                            Text("\(value) min").tag(value)
                        }
                    }
                } header: {
                    Text(tr("Your workout", "Din økt"))
                } footer: {
                    Text(tr(
                        "Coach will suggest the exercises, structure and intensity. You choose your own weights and pace.",
                        "Coach foreslår øvelser, oppsett og intensitet. Du velger selv treningsvekter og tempo."
                    ))
                }

                Section(tr("Extra preferences (optional)", "Andre ønsker (valgfritt)")) {
                    TextField(
                        tr("E.g. chest focus or 4×4 intervals", "F.eks. bryst eller 4×4-intervaller"),
                        text: $notes, axis: .vertical
                    )
                    .lineLimit(2...4)
                }

                Section {
                    Label(
                        tr("You can review your training profile and injury notes before sending anything to AI.",
                           "Du kan gjennomgå treningsprofilen og skadeopplysninger før noe sendes til AI."),
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(tr("Plan a workout", "Planlegg en økt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: continueWithCoach) {
                    Label(tr("Continue with Coach", "Fortsett med Coach"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.accentInk)
                .padding()
                .background(.regularMaterial)
            }
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func continueWithCoach() {
        let detail = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if ATHLTHLocalization.isNorwegian {
            prompt = "Lag en treningsøkt til meg. Treningsform: \(type.title). Varighet: \(duration) minutter. Treningssted: \(venue.title). Erfaring: \(level.title)." +
                (detail.isEmpty ? "" : " Mine ønsker: \(String(detail.prefix(500))).") +
                " Foreslå en komplett økt som jeg kan gjennomgå og velge å legge i kalenderen eller lagre i Mine økter. Jeg bestemmer belastning og tempo."
        } else {
            prompt = "Create a workout for me. Type: \(type.title). Duration: \(duration) minutes. Location: \(venue.title). Experience: \(level.title)." +
                (detail.isEmpty ? "" : " Preferences: \(String(detail.prefix(500))).") +
                " Propose a complete workout I can review and choose to schedule or save. I control my weights and pace."
        }
        onContinue(prompt)
    }
}
