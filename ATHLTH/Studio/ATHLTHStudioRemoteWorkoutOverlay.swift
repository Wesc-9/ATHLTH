import SwiftUI

/// iPad companion to the iPhone-owned strength session. It never edits or
/// saves workout data: only the phone/Watch remains the recording authority.
/// The compact launcher can be minimized independently of the Studio tab.
struct ATHLTHStudioRemoteWorkoutOverlay: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var remote: ATHLTHPrivateLiveStrengthSnapshot?
    @State private var expanded = false
    @State private var seenSessionID: UUID?

    var body: some View {
        Group {
            if strength.activeWorkout == nil, let remote, remote.isFresh() {
                VStack(spacing: 9) {
                    ATHLTHMinimizedWorkoutReturnPill(
                        title: ATHLTHLocalization.choose(
                            english: "Live workout", norwegian: "Pågående økt"),
                        systemImage: "dumbbell.fill",
                        detail: remote.title,
                        attention: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.20)) {
                            expanded.toggle()
                        }
                    }
                    .frame(maxWidth: 350)
                    .accessibilityIdentifier("athlth-ipad-workout-return-pill")

                    if expanded {
                        VStack(alignment: .trailing, spacing: 9) {
                            HStack {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "From your iPhone",
                                        norwegian: "Fra din iPhone"),
                                    systemImage: "iphone"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.20)) {
                                        expanded = false
                                    }
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Minimize", norwegian: "Minimer"),
                                        systemImage: "chevron.up"
                                    )
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 5)
                            ATHLTHStudioRemoteStrengthStatusCard(snapshot: remote)
                        }
                        .padding(12)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 26))
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
                        .frame(maxWidth: 590)
                        .accessibilityIdentifier("athlth-ipad-live-workout-expanded")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .task(id: "\(session.profile.userID.uuidString)-\(session.signedIn)-\(scenePhase == .active)") {
            remote = nil
            seenSessionID = nil
            expanded = false
            guard ATHLTHDeviceRole.isIPad, session.signedIn,
                  scenePhase == .active else { return }
            while !Task.isCancelled {
                let accountID = session.profile.userID
                let value = await ATHLTHPrivateLiveStrengthStatusStore.fetch(
                    for: accountID)
                guard !Task.isCancelled,
                      session.profile.userID == accountID,
                      session.signedIn else { break }
                if let value, value.id != seenSessionID {
                    seenSessionID = value.id
                    expanded = true
                }
                remote = value
                if value == nil { seenSessionID = nil }
                try? await Task.sleep(for: .seconds(value == nil ? 3 : 5))
            }
        }
    }
}
