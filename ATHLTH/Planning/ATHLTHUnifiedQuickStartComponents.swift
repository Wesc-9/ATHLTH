import SwiftUI

/// The start UI has one vocabulary for running, walking and strength.
/// These choices only determine what gets selected in the existing launch
/// coordinator; they never create a second workout or recording engine.
enum ATHLTHQuickStartActivity {
    case running, walking, strength

    var title: String {
        switch self {
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        }
    }

    var symbol: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell"
        }
    }

    var types: [ATHLTHQuickStartType] {
        switch self {
        case .running: return [.free, .route, .workout]
        case .walking: return [.free, .route]
        case .strength: return [.free, .workout, .exercises]
        }
    }
}

enum ATHLTHQuickStartType: String, Identifiable {
    case free, route, workout, exercises
    var id: String { rawValue }

    func title(for activity: ATHLTHQuickStartActivity) -> String {
        switch self {
        case .free:
            switch activity {
            case .running: return ATHLTHLocalization.choose(
                english: "Free running", norwegian: "Fri løping")
            case .walking: return ATHLTHLocalization.choose(
                english: "Free walking", norwegian: "Fri gåing")
            case .strength: return ATHLTHLocalization.choose(
                english: "Free strength", norwegian: "Fri styrkeøkt")
            }
        case .route: return ATHLTHLocalization.choose(
            english: "Route", norwegian: "Rute")
        case .workout: return ATHLTHLocalization.choose(
            english: "Training workout", norwegian: "Treningsøkt")
        case .exercises: return ATHLTHLocalization.choose(
            english: "Add exercises", norwegian: "Legg til øvelser")
        }
    }

    func subtitle(for activity: ATHLTHQuickStartActivity) -> String {
        switch self {
        case .free: return ATHLTHLocalization.choose(
            english: "Start now, without a plan.",
            norwegian: "Start direkte uten en plan.")
        case .route: return ATHLTHLocalization.choose(
            english: "Follow a saved route.",
            norwegian: "Følg en lagret rute.")
        case .workout: return ATHLTHLocalization.choose(
            english: "Use a workout from your library.",
            norwegian: "Velg en økt fra biblioteket.")
        case .exercises: return ATHLTHLocalization.choose(
            english: "Choose exercises before starting.",
            norwegian: "Velg øvelser før start.")
        }
    }

    var symbol: String {
        switch self {
        case .free: return "play.circle"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .workout: return "list.bullet.clipboard"
        case .exercises: return "plus.circle"
        }
    }
}

/// A consistent type selector, with a compact Basic layout and a more
/// descriptive Advanced layout. Source pickers stay owned by each activity.
struct ATHLTHQuickStartTypeSelector: View {
    let activity: ATHLTHQuickStartActivity
    let advanced: Bool
    @Binding var selection: ATHLTHQuickStartType
    var routeAllowed = true
    let onChoose: (ATHLTHQuickStartType) -> Void

    private var types: [ATHLTHQuickStartType] { activity.types }

    var body: some View {
        VStack(alignment: .leading, spacing: advanced ? 10 : 8) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Workout type", norwegian: "Velg type"))
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                if advanced {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose one", norwegian: "Velg én"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            ForEach(types) { type in
                let unavailable = type == .route && !routeAllowed
                Button {
                    guard !unavailable else { return }
                    selection = type
                    onChoose(type)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: type.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: advanced ? 43 : 32,
                                   height: advanced ? 43 : 32)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(type.title(for: activity))
                                .font(advanced ? .headline : .subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            if advanced {
                                Text(type.subtitle(for: activity))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                        Spacer(minLength: 5)
                        Image(systemName: selection == type
                              ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(selection == type
                                ? ATHLTHPlanDesign.accentInk
                                : ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: advanced ? 70 : 54)
                    .background(
                        selection == type ? ATHLTHPlanDesign.selectedSurface : Color.white,
                        in: RoundedRectangle(cornerRadius: 17))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(
                                ATHLTHPlanDesign.outline,
                                lineWidth: selection == type ? 1.4 : 0.65)
                    }
                    .contentShape(Rectangle())
                }
                .disabled(unavailable)
                .opacity(unavailable ? 0.45 : 1)
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-quick-type-\(type.rawValue)")
            }
        }
    }
}

/// Basic deliberately omits the full editable name, environment and detailed
/// prescriptions card. Advanced keeps the established workout details view.
struct ATHLTHQuickStartSimpleDetailsCard: View {
    let activity: ATHLTHQuickStartActivity
    let summary: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: activity.symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 46, height: 46)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.75)
        }
        .accessibilityIdentifier("athlth-quick-basic-details")
    }
}

enum ATHLTHQuickStartTool: String, CaseIterable, Identifiable {
    case spotify, guidance, equipment, companion, partner, iPad
    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .guidance: return ATHLTHLocalization.choose(
            english: "Coach & guidance", norwegian: "Coach og veiledning")
        case .equipment: return ATHLTHLocalization.choose(
            english: "Equipment", norwegian: "Utstyr")
        case .companion: return ATHLTHLocalization.choose(
            english: "Walking companion", norwegian: "Turkamerat")
        case .partner: return ATHLTHLocalization.choose(
            english: "Training partner", norwegian: "Treningspartner")
        case .iPad: return ATHLTHLocalization.choose(
            english: "Show on iPad", norwegian: "Vis på iPad")
        }
    }

    var symbol: String {
        switch self {
        case .spotify: return "music.note"
        case .guidance: return "waveform"
        case .equipment: return "backpack"
        case .companion: return "pawprint"
        case .partner: return "person.2"
        case .iPad: return "ipad"
        }
    }
}

/// One expandable tool strip across all Quick Train activities. Advanced
/// exposes the strip immediately; Basic keeps the same choices behind one
/// small button. A disconnected Spotify chip looks inactive but can request
/// an explicit authorization, never silently start playing.
struct ATHLTHQuickStartToolsRow<Detail: View>: View {
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    let activity: ATHLTHQuickStartActivity
    let advanced: Bool
    @Binding var showOnIPad: Bool
    let iPadAvailable: Bool
    let detail: (ATHLTHQuickStartTool) -> Detail

    @State private var selected: ATHLTHQuickStartTool?
    @State private var basicExpanded = false
    @State private var confirmSpotifyConnect = false

    private var available: [ATHLTHQuickStartTool] {
        ATHLTHQuickStartTool.allCases.filter {
            if $0 == .companion && activity == .strength { return false }
            if $0 == .iPad { return iPadAvailable }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !advanced {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        basicExpanded.toggle()
                        if !basicExpanded { selected = nil }
                    }
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(ATHLTHLocalization.choose(
                            english: "More settings", norwegian: "Flere innstillinger"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Spacer()
                        Image(systemName: basicExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(15)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-quick-more-settings")
            }

            if advanced || basicExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(available) { tool in
                            Button {
                                switch tool {
                                case .iPad:
                                    showOnIPad.toggle()
                                case .spotify where !spotify.isConnected:
                                    confirmSpotifyConnect = true
                                default:
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selected = selected == tool ? nil : tool
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: tool.symbol)
                                    Text(tool.title)
                                        .lineLimit(1)
                                    if tool == .iPad, showOnIPad {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    tool == .spotify && !spotify.isConnected
                                        ? ATHLTHPlanDesign.secondaryInk
                                        : selected == tool || (tool == .iPad && showOnIPad)
                                            ? Color.white : ATHLTHPlanDesign.ink
                                )
                                .padding(.horizontal, 12)
                                .frame(height: 41)
                                .background(
                                    selected == tool || (tool == .iPad && showOnIPad)
                                        ? ATHLTHPlanDesign.accentInk :
                                        tool == .spotify && !spotify.isConnected
                                            ? Color.gray.opacity(0.12)
                                            : ATHLTHPlanDesign.selectedSurface,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("athlth-quick-tool-\(tool.rawValue)")
                            .accessibilityAddTraits(
                                selected == tool || (tool == .iPad && showOnIPad)
                                    ? .isSelected : []
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }

                if let selected, selected != .iPad {
                    VStack(alignment: .leading, spacing: 10) {
                        detail(selected)
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
                    }
                }
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Connect Spotify?",
                norwegian: "Vil du koble til Spotify?"),
            isPresented: $confirmSpotifyConnect,
            titleVisibility: .visible
        ) {
            if spotify.isConfigured {
                Button(ATHLTHLocalization.choose(
                    english: "Connect Spotify", norwegian: "Koble til Spotify")) {
                    spotify.connect()
                }
            }
            Button(ATHLTHLocalization.choose(
                english: "Not now", norwegian: "Ikke nå"), role: .cancel) {}
        } message: {
            Text(spotify.isConfigured
                 ? ATHLTHLocalization.choose(
                    english: "Connect your Spotify account to select a playlist.",
                    norwegian: "Koble til Spotify-kontoen for å velge spilleliste.")
                 : ATHLTHLocalization.choose(
                    english: "Spotify is not configured in this build.",
                    norwegian: "Spotify er ikke konfigurert i denne versjonen."))
        }
    }
}
