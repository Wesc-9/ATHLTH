import SwiftUI

/// Optional source context, separate from the executable workout prescription.
/// The licensed Zoned source provides these English notes for every workout.
/// Keep the original wording rather than silently mistranslating instructions.
struct ATHLTHZonedWorkoutGuidanceCard: View {
    let workout: ATHLTHZonedPlanLibrary.Workout
    @State private var expanded = false

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 15) {
                Text(tr(
                    "Original coaching guidance is provided in English.",
                    "Rådene nedenfor er hentet direkte fra kilden og står på engelsk."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                if let tips = workout.coachingTipsEn, !tips.isEmpty {
                    guidanceSection(
                        tr("Coaching tips", "Trenerråd"),
                        icon: "lightbulb",
                        entries: tips
                    )
                }
                if let mistakes = workout.commonMistakesEn, !mistakes.isEmpty {
                    guidanceSection(
                        tr("Common mistakes", "Vanlige feil"),
                        icon: "exclamationmark.triangle",
                        entries: mistakes
                    )
                }
                if let environment = workout.environment {
                    let guidance = environmentGuidance(environment)
                    if !guidance.isEmpty {
                        guidanceSection(
                            tr("Recommended surroundings", "Treningsmiljø"),
                            icon: "mountain.2",
                            entries: guidance
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 15)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(tr("Workout guidance", "Gjennomføring og råd"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer(minLength: 8)
            }
        }
        .tint(ATHLTHPlanDesign.accentInk)
        .padding(16)
        .athlthPlanCard(radius: 19)
        .accessibilityIdentifier("athlth-zoned-workout-original-guidance")
    }

    private func guidanceSection(
        _ label: String,
        icon: String,
        entries: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .padding(.top, 7)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(entry)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func environmentGuidance(
        _ environment: ATHLTHZonedPlanLibrary.Environment
    ) -> [String] {
        var items: [String] = []
        if environment.requiresHills == true {
            items.append(tr("Hills required", "Bakker kreves"))
        }
        if environment.requiresTrack == true {
            items.append(tr("Running track required", "Løpebane kreves"))
        }
        if environment.prefersFlat == true {
            items.append(tr("Prefer flat terrain", "Helst flatt underlag"))
        }
        if environment.prefersSoft == true {
            items.append(tr("Prefer soft surface", "Helst mykt underlag"))
        }
        return items
    }
}
