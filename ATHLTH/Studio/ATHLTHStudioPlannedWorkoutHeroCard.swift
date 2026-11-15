import SwiftUI

/// The selected day's featured workout on iPad Home. This is a read-only
/// presentation of the same PlannedSession used by Plan Studio and the
/// workout launcher; it never fabricates session targets or start times.
struct ATHLTHStudioPlannedWorkoutHeroCard: View {
    let workout: PlannedSession
    let availableWidth: CGFloat
    let isCompleted: Bool
    let isSkipped: Bool
    let canStart: Bool
    let onOpen: () -> Void
    let onStart: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let canvas = ATHLTHStudioStyle.canvas
    private let outline = ATHLTHStudioStyle.outline

    private var horizontal: Bool {
        availableWidth >= 760 && !dynamicTypeSize.isAccessibilitySize
    }

    private var mediaWidth: CGFloat {
        min(365, max(230, (availableWidth - 100) * 0.35))
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private struct Fact: Identifiable {
        let id: String
        let icon: String
        let text: String
    }

    private var facts: [Fact] {
        let startText = workout.scheduledStart.map {
            $0.formatted(date: .omitted, time: .shortened)
        } ?? tr("Time not set", "Uten klokkeslett")
        var values = [Fact(id: "start", icon: "clock", text: startText)]

        if let duration = ATHLTHPlannedWorkoutPresentation.duration(for: workout) {
            values.append(Fact(id: "duration", icon: "timer", text: duration))
        }
        if let km = workout.targetDistanceKilometers, km.isFinite, km > 0 {
            values.append(Fact(
                id: "distance", icon: "point.topleft.down.to.point.bottomright.curvepath",
                text: String(format: "%.1f km", km)
            ))
        }
        if let pace = workout.targetPaceSecondsPerKilometer,
           pace.isFinite, (120...1200).contains(pace) {
            let seconds = Int(pace.rounded())
            values.append(Fact(
                id: "pace", icon: "speedometer",
                text: String(format: "%d:%02d /km", seconds / 60, seconds % 60)
            ))
        }
        let zones = Set(workout.resolvedWorkoutBlocks.compactMap {
            $0.targetHeartRateZone
        }.filter { (1...5).contains($0) }).sorted()
        if let low = zones.first, let high = zones.last {
            values.append(Fact(
                id: "zone", icon: "heart",
                text: low == high ? tr("Zone \(low)", "Sone \(low)") :
                    tr("Zones \(low)–\(high)", "Soner \(low)–\(high)")
            ))
        }
        return values
    }

    private var features: [Fact] {
        var items: [Fact] = []
        if workout.audioCoachConfiguration?.enabled == true {
            items.append(Fact(id: "coach", icon: "waveform",
                              text: "Audio Coach"))
        }
        if workout.routeID != nil {
            items.append(Fact(id: "route", icon: "map",
                              text: tr("Route", "Rute")))
        }
        if workout.ghostTargetDurationSeconds != nil {
            items.append(Fact(id: "ghost", icon: "figure.run",
                              text: "Ghost Race"))
        }
        if workout.resolvedWorkoutBlocks.contains(where: {
            $0.isIndoor == true || $0.treadmillInclinePercent != nil
        }) {
            items.append(Fact(id: "treadmill", icon: "figure.run",
                              text: tr("Treadmill", "Tredemølle")))
        }
        return items
    }

    private var workoutSummary: String? {
        if let summary = ATHLTHWorkoutContentSummary.text(for: workout),
           !summary.isEmpty {
            return summary
        }
        if !workout.exercises.isEmpty {
            return tr("\(workout.exercises.count) exercises",
                      "\(workout.exercises.count) øvelser")
        }
        let firstLine = workout.notes?
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return firstLine.map { String($0.prefix(160)) }
    }

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: 0) {
                    image
                        .frame(width: mediaWidth, height: 225)
                    information
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    image
                        .frame(height: 170)
                    information
                        .padding(15)
                }
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(outline.opacity(0.6), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
    }

    private var image: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image(ATHLTHPlanWorkoutArtwork.asset(for: workout))
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.10), .black.opacity(0.67)],
                    startPoint: .top, endPoint: .bottom
                )

                Label(ATHLTHPlanWorkoutArtwork.label(for: workout).uppercased(),
                      systemImage: workout.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 28)
                    .background(.black.opacity(0.28), in: Capsule())
                    .padding(14)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("PLANNED WORKOUT", "PLANLAGT ØKT"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(gold)
                Spacer(minLength: 0)
                if isCompleted {
                    Label(tr("Completed", "Fullført"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ink)
                } else if isSkipped {
                    Label(tr("Skipped", "Hoppet over"), systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2.weight(.medium))

            Text(workout.title)
                .font(.system(size: horizontal ? 21 : 19, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = workoutSummary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: horizontal ? 116 : 110),
                                   spacing: 7)],
                alignment: .leading, spacing: 7
            ) {
                ForEach(facts) { fact in
                    Label(fact.text, systemImage: fact.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 28,
                               alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(canvas, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !features.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 11) {
                        ForEach(features) { feature in featureLabel(feature) }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(features) { feature in featureLabel(feature) }
                    }
                }
            }

            HStack(spacing: 8) {
                if canStart {
                    Button(action: onStart) {
                        Label(tr("Start workout", "Start økt"),
                              systemImage: "play.fill")
                            .frame(minHeight: 38)
                            .padding(.horizontal, 13)
                            .foregroundStyle(.white)
                            .background(ink, in: Capsule())
                    }
                    .accessibilityIdentifier("athlth-ipad-featured-workout-start")
                }

                Button(action: onOpen) {
                    Label(tr("Workout details", "Øktdetaljer"),
                          systemImage: "arrow.up.right")
                        .frame(minHeight: 38)
                        .padding(.horizontal, 12)
                        .foregroundStyle(ink)
                        .background(canvas, in: Capsule())
                }
                .accessibilityIdentifier("athlth-ipad-featured-workout-details")
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureLabel(_ feature: Fact) -> some View {
        Label(feature.text, systemImage: feature.icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(gold)
            .lineLimit(1)
    }
}
