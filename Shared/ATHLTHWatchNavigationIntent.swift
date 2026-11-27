#if os(watchOS)
import AppIntents
import Foundation

@available(watchOS 26.0, *)
enum ATHLTHWatchNavigationTarget: String, AppEnum {
    case today, dailyForm, sent, ghost, favorites

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "ATHLTH" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.today: "Dagens økt", .dailyForm: "Dagens form", .sent: "Sendt til klokken",
         .ghost: "Ghost Race", .favorites: "Favorittøkter"]
    }
}

/// Included in the Watch app and widget target. Navigation is handled by
/// the foreground SwiftUI root, never by the widget extension recorder.
@available(watchOS 26.0, *)
struct ATHLTHWatchNavigationIntent: OpenIntent, TargetContentProvidingIntent {
    static var title: LocalizedStringResource { "Åpne ATHLTH" }
    @Parameter(title: "Visning") var target: ATHLTHWatchNavigationTarget

    init() { target = .today }
    init(target: ATHLTHWatchNavigationTarget) { self.target = target }
}
#endif
