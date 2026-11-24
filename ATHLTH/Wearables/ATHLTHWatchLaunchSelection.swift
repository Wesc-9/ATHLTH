import SwiftUI

/// Recording-device preference is independent of the source used for health data.
enum ATHLTHPreferredWatch: String, CaseIterable, Identifiable {
    case automatic, appleWatch, garmin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return ATHLTHLocalization.choose(english: "Automatic", norwegian: "Automatisk")
        case .appleWatch: return "Apple Watch"
        case .garmin: return "Garmin"
        }
    }
}

enum ATHLTHWatchLaunchPolicy {
    /// Never silently start on a different watch when a specific default is unavailable.
    /// An automatic preference with multiple live devices requires explicit selection.
    static func resolve(preference: ATHLTHPreferredWatch, apple: Bool, garmin: Bool) -> ATHLTHPreferredWatch? {
        switch preference {
        case .automatic:
            if apple && !garmin { return .appleWatch }
            if garmin && !apple { return .garmin }
            return nil
        case .appleWatch: return apple ? .appleWatch : nil
        case .garmin: return garmin ? .garmin : nil
        }
    }
}

@MainActor
struct ATHLTHWatchLaunchSelection: DynamicProperty {
    @AppStorage("settings.preferredLiveWatch") private var stored = ATHLTHPreferredWatch.automatic.rawValue
    #if ATHLTH_GARMIN_PERSONAL && DEBUG
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject private var garminStore = GarminPersonalLocalStore.shared
    #endif

    var preference: ATHLTHPreferredWatch {
        ATHLTHPreferredWatch(rawValue: stored) ?? .automatic
    }

    var binding: Binding<ATHLTHPreferredWatch> {
        Binding(get: { preference }, set: { stored = $0.rawValue })
    }

    var garminDataConnected: Bool {
        #if ATHLTH_GARMIN_PERSONAL && DEBUG
        return session.signedIn && !session.previewModeEnabled &&
            garminStore.isConnected(to: session.profile.userID)
        #else
        return false
        #endif
    }

    func resolve(apple: Bool, garmin: Bool) -> ATHLTHPreferredWatch? {
        ATHLTHWatchLaunchPolicy.resolve(preference: preference, apple: apple, garmin: garmin)
    }
}

struct ATHLTHPreferredWatchPicker: View {
    var selection: ATHLTHWatchLaunchSelection
    /// Must be true only after a real Garmin live adapter becomes available.
    var garminLiveAvailable = false

    var body: some View {
        Menu {
            ForEach(ATHLTHPreferredWatch.allCases) { option in
                if option != .garmin || selection.garminDataConnected || garminLiveAvailable ||
                    selection.preference == .garmin {
                    Button {
                        selection.binding.wrappedValue = option
                    } label: {
                        Label(option.title, systemImage: selection.preference == option ? "checkmark" : "watch.analog")
                    }
                    .disabled(option == .garmin && !garminLiveAvailable)
                }
            }
        } label: {
            HStack {
                Label(ATHLTHLocalization.choose(english: "Preferred watch", norwegian: "Foretrukket klokke"),
                      systemImage: "watch.analog")
                Spacer()
                Text(selection.preference.title)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ATHLTHTheme.primaryText)
        }
        if selection.garminDataConnected && !garminLiveAvailable {
            Text(ATHLTHLocalization.choose(
                english: "Garmin is connected for data sync. Direct workout start is not yet supported.",
                norwegian: "Garmin er tilkoblet for datasynkronisering. Direkte øktstart støttes ikke ennå."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }
}

/// Reused by context menus and fallback dialogs. Never routes Garmin to Apple Watch.
struct ATHLTHWatchLaunchChoices: View {
    let appleAvailable: Bool
    let garminAvailable: Bool
    let garminConnected: Bool
    let onAppleWatch: () -> Void
    let onGarmin: (() -> Void)?

    var body: some View {
        Button(action: onAppleWatch) {
            Label("Apple Watch", systemImage: "applewatch")
        }
        .disabled(!appleAvailable)
        if garminConnected || garminAvailable {
            Button {
                guard garminAvailable else { return }
                onGarmin?()
            } label: {
                Label(garminAvailable ? "Garmin" : ATHLTHLocalization.choose(
                    english: "Garmin · sync only", norwegian: "Garmin · kun datasynk"
                ), systemImage: "watch.analog")
            }
            .disabled(!garminAvailable || onGarmin == nil)
        }
    }
}
