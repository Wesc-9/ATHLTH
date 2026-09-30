import SwiftUI
import WidgetKit

private struct ATHLTHWatchWidgetEntry:
    TimelineEntry
{
    let date: Date
}

private struct ATHLTHWatchWidgetProvider:
    TimelineProvider
{
    func placeholder(
        in context: Context
    ) -> ATHLTHWatchWidgetEntry {
        ATHLTHWatchWidgetEntry(
            date: Date()
        )
    }

    func getSnapshot(
        in context: Context,
        completion:
            @escaping (
                ATHLTHWatchWidgetEntry
            ) -> Void
    ) {
        completion(
            ATHLTHWatchWidgetEntry(
                date: Date()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion:
            @escaping (
                Timeline<
                    ATHLTHWatchWidgetEntry
                >
            ) -> Void
    ) {
        completion(
            Timeline(
                entries: [
                    ATHLTHWatchWidgetEntry(
                        date: Date()
                    )
                ],
                policy: .never
            )
        )
    }
}

private struct ATHLTHWatchWidgetView:
    View
{
    @Environment(\.widgetFamily)
    private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(
                    "ATHLTH · Quick Run",
                    systemImage: "figure.run"
                )

            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()

                    Image(
                        systemName:
                            "figure.run"
                    )
                    .font(
                        .system(
                            size: 22,
                            weight: .bold
                        )
                    )
                }

            default:
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            "figure.run"
                    )
                    .font(
                        .system(
                            size: 23,
                            weight: .bold
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 1
                    ) {
                        Text("ATHLTH")
                            .font(
                                .caption2
                                    .weight(.bold)
                            )

                        Text("Quick Run")
                            .font(
                                .headline
                                    .weight(.semibold)
                            )
                            .minimumScaleFactor(
                                0.8
                            )
                            .lineLimit(1)
                    }

                    Spacer(
                        minLength: 0
                    )
                }
            }
        }
        .widgetURL(
            URL(
                string:
                    "athlth-watch://quick-run"
            )
        )
        .containerBackground(
            .clear,
            for: .widget
        )
    }
}

struct ATHLTHQuickRunWatchWidget:
    Widget
{
    let kind =
        "ATHLTHQuickRunWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider:
                ATHLTHWatchWidgetProvider()
        ) { entry in
            ATHLTHWatchWidgetView()
        }
        .configurationDisplayName(
            "ATHLTH Quick Run"
        )
        .description(
            "Start an ATHLTH run from your watch face or Smart Stack."
        )
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct ATHLTHWatchWidgetsBundle:
    WidgetBundle
{
    var body: some Widget {
        ATHLTHQuickRunWatchWidget()
    }
}
