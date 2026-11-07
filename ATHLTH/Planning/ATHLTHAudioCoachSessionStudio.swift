import SwiftUI

/// Session-scoped Audio Coach. The single active-list workspace edits the
/// original Watch configuration draft without altering global defaults.
struct ATHLTHAudioCoachSessionStudio: View {
    @Binding var draft: AudioCoachDraft
    let showRouteOptions: Bool
    let showStructuredOptions: Bool

    var body: some View {
        ATHLTHAudioCoachActiveListView(
            draft: $draft,
            showRouteOptions: showRouteOptions,
            showStructuredOptions: showStructuredOptions
        )
    }
}
