import SwiftUI
import WidgetKit

// Different Watch-face choices, not just alternate artwork for Quick Run.
// Keep the original Quick Run kind to preserve existing Watch-face placements.
private enum ATHLTHWatchShortcut: String {
    case home, run, strength, walk, ghost, today, routes

    var kind: String {
        switch self {
        case .home: return "ATHLTHOpenAppWatchWidget"
        case .run: return "ATHLTHQuickRunWatchWidget"
        case .strength: return "ATHLTHQuickStrengthWatchWidget"
        case .walk: return "ATHLTHQuickWalkWatchWidget"
        case .ghost: return "ATHLTHGhostRaceWatchWidget"
        case .today: return "ATHLTHTodayWorkoutWatchWidget"
        case .routes: return "ATHLTHRoutesWatchWidget"
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
        }
    }
}

private struct ATHLTHWatchWidgetEntry: TimelineEntry {
    let date: Date
}

private struct ATHLTHWatchWidgetProvider: TimelineProvider {
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
            provider: ATHLTHWatchWidgetProvider()
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
    }
}
