import SwiftUI
import WidgetKit
import AppIntents
import RelevanceKit

// Different Watch-face choices, not just alternate artwork for Quick Run.
// Keep the original Quick Run kind to preserve existing Watch-face placements.
private enum ATHLTHWatchShortcut: String {
    case home, run, strength, walk, ghost, today, routes, sent

    var kind: String {
        switch self {
        case .home: return "ATHLTHOpenAppWatchWidget"
        case .run: return "ATHLTHQuickRunWatchWidget"
        case .strength: return "ATHLTHQuickStrengthWatchWidget"
        case .walk: return "ATHLTHQuickWalkWatchWidget"
        case .ghost: return "ATHLTHGhostRaceWatchWidget"
        case .today: return "ATHLTHTodayWorkoutWatchWidget"
        case .routes: return "ATHLTHRoutesWatchWidget"
        case .sent: return "ATHLTHSentWorkoutsWatchWidget"
        }
    }

    var title: String {
        switch self {
        case .home: return "Åpne app"
        case .run: return "Løping"
        case .strength: return "Styrke"
        case .walk: return "Gåtur"
        case .ghost: return "Ghost Race"
        case .today: return "Dagens økt"
        case .routes: return "Ruter"
        case .sent: return "Sendt til klokken"
        }
    }

    var displayName: String { "ATHLTH · \(title)" }

    var caption: String {
        switch self {
        case .home: return "Åpne ATHLTH"
        case .run: return "Start løpetur"
        case .strength: return "Start styrkeøkt"
        case .walk: return "Start gåtur"
        case .ghost: return "Konkurrer med Ghost"
        case .today: return "Dagens trening"
        case .routes: return "Velg en rute"
        case .sent: return "Klargjorte økter"
        }
    }

    var description: String {
        switch self {
        case .home: return "Åpne ATHLTHs startskjerm direkte fra urskiven. Starter ingen økt."
        case .run: return "Start løping direkte fra urskiven."
        case .strength: return "Start styrketrening direkte fra urskiven."
        case .walk: return "Start en gåtur direkte fra urskiven."
        case .ghost: return "Åpne Ghost Race på klokken. Start bare en Ghost-økt som er klargjort fra iPhone."
        case .today: return "Start dagens planlagte treningsøkt når den er tilgjengelig."
        case .routes: return "Åpne lagrede ATHLTH-ruter på klokken."
        case .sent: return "Åpne økter sendt til Apple Watch. Starter ingen økt automatisk."
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .run: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .walk: return "figure.walk"
        case .ghost: return "scope"
        case .today: return "calendar.badge.clock"
        case .routes: return "map.fill"
        case .sent: return "applewatch.and.arrow.forward"
        }
    }

    var deepLink: URL? {
        switch self {
        case .home: return URL(string: "athlth-watch://home")
        case .run: return URL(string: "athlth-watch://quick-run")
        case .strength: return URL(string: "athlth-watch://quick-strength")
        case .walk: return URL(string: "athlth-watch://quick-walk")
        case .ghost: return URL(string: "athlth-watch://ghost-race")
        case .today: return URL(string: "athlth-watch://today")
        case .routes: return URL(string: "athlth-watch://routes")
        case .sent: return URL(string: "athlth-watch://sent")
        }
    }
}

private struct ATHLTHWatchWidgetEntry: TimelineEntry {
    let date: Date
}

private struct ATHLTHWatchWidgetProvider: TimelineProvider {
    var shortcut: ATHLTHWatchShortcut = .home

    @available(watchOS 26.0, *)
    func relevance() async -> WidgetRelevance<Void> {
        guard shortcut == .today,
              let date = ATHLTHWatchScheduleRelevance.read(from: UserDefaults(suiteName: ATHLTHWatchFaceFormSnapshot.suite)),
              date.addingTimeInterval(30 * 60) > Date()
        else { return WidgetRelevance([]) }
        let context = RelevantContext.date(from: date.addingTimeInterval(-30 * 60), to: date.addingTimeInterval(30 * 60))
        return WidgetRelevance([WidgetRelevanceAttribute(context: context)])
    }
    func placeholder(in context: Context) -> ATHLTHWatchWidgetEntry {
        ATHLTHWatchWidgetEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ATHLTHWatchWidgetEntry) -> Void
    ) {
        completion(ATHLTHWatchWidgetEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ATHLTHWatchWidgetEntry>) -> Void
    ) {
        completion(Timeline(
            entries: [ATHLTHWatchWidgetEntry(date: Date())],
            policy: .never
        ))
    }
}

private struct ATHLTHWatchShortcutView: View {
    @Environment(\.widgetFamily) private var family

    let shortcut: ATHLTHWatchShortcut

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if shortcut == .home {
                    HStack(spacing: 4) {
                        ATHLTHMarkShape()
                            .fill(.primary)
                            .frame(width: 17, height: 13)
                        Text("ATHLTH")
                            .fontWeight(.semibold)
                    }
                } else {
                    Label(shortcut.title, systemImage: shortcut.symbol)
                }

            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    if shortcut == .home {
                        // The original vector pulse-A, not a generic house icon.
                        // SwiftUI's primary colour adapts to the Watch face's
                        // monochrome and tinted complication rendering.
                        ATHLTHMarkShape()
                            .fill(.primary)
                            .frame(width: 32, height: 26)
                    } else {
                        Image(systemName: shortcut.symbol)
                            .font(.system(size: 23, weight: .semibold))
                    }
                }

            case .accessoryCorner:
                if shortcut == .home {
                    ATHLTHMarkShape()
                        .fill(.primary)
                        .frame(width: 30, height: 25)
                        .widgetLabel {
                            Text("ATHLTH")
                        }
                }

            default:
                HStack(spacing: 9) {
                    if shortcut == .home {
                        ATHLTHMarkShape()
                            .fill(.primary)
                            .frame(width: 35, height: 28)
                            .frame(width: 39)
                    } else {
                        Image(systemName: shortcut.symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .frame(width: 30)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if shortcut == .home {
                            Text("ATHLTH")
                                .font(.headline.weight(.heavy))
                                .lineLimit(1)
                            Text(shortcut.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("ATHLTH")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(shortcut.title)
                                .font(.headline.weight(.semibold))
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.displayName)
        .widgetURL(shortcut.deepLink)
        .containerBackground(.clear, for: .widget)
    }
}

private struct ATHLTHWatchShortcutWidget: Widget {
    let shortcut: ATHLTHWatchShortcut

    // Widget requires init() in Xcode 27 / watchOS 27. The explicit
    // shortcut initializer is used for each separate complication kind.
    init() {
        self.shortcut = .run
    }

    init(shortcut: ATHLTHWatchShortcut) {
        self.shortcut = shortcut
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: shortcut.kind,
            provider: ATHLTHWatchWidgetProvider(shortcut: shortcut)
        ) { _ in
            ATHLTHWatchShortcutView(shortcut: shortcut)
        }
        .configurationDisplayName(shortcut.displayName)
        .description(shortcut.description)
        .supportedFamilies(
            shortcut == .home
                ? [.accessoryCircular, .accessoryRectangular,
                   .accessoryInline, .accessoryCorner]
                : [.accessoryCircular, .accessoryRectangular,
                   .accessoryInline]
        )
    }
}

private struct ATHLTHDailyFormEntry: TimelineEntry {
    let date: Date
    let score: Int?
}

private struct ATHLTHDailyFormProvider: TimelineProvider {
    func placeholder(in context: Context) -> ATHLTHDailyFormEntry {
        ATHLTHDailyFormEntry(date: Date(), score: nil)
    }

    private func entry(at date: Date) -> ATHLTHDailyFormEntry {
        let snapshot = ATHLTHWatchFaceFormSnapshot.read(
            from: UserDefaults(suiteName: ATHLTHWatchFaceFormSnapshot.suite)
        )
        return ATHLTHDailyFormEntry(date: date, score: snapshot?.currentScore(at: date))
    }

    func getSnapshot(in context: Context, completion: @escaping (ATHLTHDailyFormEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ATHLTHDailyFormEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var entries = [current]
        if current.score != nil, let midnight = ATHLTHWatchFaceFormSnapshot.nextDay(after: now) {
            entries.append(ATHLTHDailyFormEntry(date: midnight, score: nil))
        }
        // The Watch app invalidates this timeline when a new score arrives.
        completion(Timeline(entries: entries, policy: .never))
    }
}

private struct ATHLTHDailyFormComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ATHLTHDailyFormEntry

    private var scoreText: String { entry.score.map(String.init) ?? "–" }

    private var ring: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.22), lineWidth: 3)
            if let score = entry.score {
                Circle().trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(scoreText)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .padding(4)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Form \(scoreText)", systemImage: "heart.circle")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    ring.padding(2)
                }
            default:
                HStack(spacing: 6) {
                    ring.frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dagens form").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        Text(entry.score == nil ? "Ikke tilgjengelig" : "\(scoreText) / 100")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ATHLTH · Dagens form")
        .accessibilityValue(entry.score.map { "\($0) av 100" } ?? "Ikke tilgjengelig")
        .privacySensitive()
        .widgetURL(URL(string: "athlth-watch://daily-form"))
        .containerBackground(.clear, for: .widget)
    }
}

private struct ATHLTHDailyFormWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ATHLTHWatchFaceFormSnapshot.widgetKind,
                            provider: ATHLTHDailyFormProvider()) { entry in
            ATHLTHDailyFormComplicationView(entry: entry)
        }
        .configurationDisplayName("ATHLTH · Dagens form")
        .description("Vis dagens synkroniserte formscore. Trykk for å se detaljer.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@available(watchOS 26.0, *)
private struct ATHLTHWatchNavigationControl: ControlWidget {
    let target: ATHLTHWatchNavigationTarget
    let name: String
    let symbol: String

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.wesc9.athlth.watch.control.\(target.rawValue)") {
            ControlWidgetButton(action: ATHLTHWatchNavigationIntent(target: target)) {
                Label(name, systemImage: symbol)
            }
        }
        .displayName("ATHLTH · \(name)")
        .description("Åpne valgt visning i ATHLTH.")
    }
}

@main
struct ATHLTHWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ATHLTHWatchShortcutWidget(shortcut: .home)
        ATHLTHWatchShortcutWidget(shortcut: .run)
        ATHLTHWatchShortcutWidget(shortcut: .strength)
        ATHLTHWatchShortcutWidget(shortcut: .walk)
        ATHLTHWatchShortcutWidget(shortcut: .ghost)
        ATHLTHWatchShortcutWidget(shortcut: .today)
        ATHLTHWatchShortcutWidget(shortcut: .routes)
        ATHLTHWatchShortcutWidget(shortcut: .sent)
        ATHLTHDailyFormWatchWidget()
        if #available(watchOS 26.0, *) {
            ATHLTHWatchNavigationControl(target: .today, name: "Dagens økt", symbol: "calendar.badge.clock")
            ATHLTHWatchNavigationControl(target: .dailyForm, name: "Dagens form", symbol: "heart.text.square")
            ATHLTHWatchNavigationControl(target: .sent, name: "Sendt til klokken", symbol: "applewatch.and.arrow.forward")
            ATHLTHWatchNavigationControl(target: .ghost, name: "Ghost Race", symbol: "scope")
            ATHLTHWatchNavigationControl(target: .favorites, name: "Favorittøkter", symbol: "star")
        }
    }
}
