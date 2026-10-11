import Foundation
import SwiftUI

// MARK: - Arena draft foundation
// This is deliberately separate from ATHLTHChallenge and Weekly Challenge.
// Drafts are local to their creator until a server-authorized multiplayer
// workflow (invites, approval, results) has been implemented.

enum ATHLTHArenaScope: String, CaseIterable, Codable, Identifiable {
    case duel
    case friends
    case club

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duel: return ATHLTHLocalization.choose(english: "1 vs 1", norwegian: "1 mot 1")
        case .friends: return ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner")
        case .club: return "Club"
        }
    }

    var symbol: String {
        switch self {
        case .duel: return "person.2.fill"
        case .friends: return "person.3.fill"
        case .club: return "shield.lefthalf.filled"
        }
    }
}

enum ATHLTHArenaScoring: String, CaseIterable, Codable, Identifiable {
    case winner = "winner"
    case podium = "podium"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winner:
            return ATHLTHLocalization.choose(
                english: "Winner gets 1 point",
                norwegian: "Vinneren får 1 poeng"
            )
        case .podium:
            return ATHLTHLocalization.choose(
                english: "Podium: 3 / 2 / 1 points",
                norwegian: "Pall: 3 / 2 / 1 poeng"
            )
        }
    }
}

enum ATHLTHArenaRoundTemplate: String, CaseIterable, Codable, Identifiable {
    case fastest5K
    case fastest1K
    case mostDistance
    case mostWorkouts
    case mostRepetitions
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastest5K: return ATHLTHLocalization.choose(english: "Fastest 5 km", norwegian: "Raskeste 5 km")
        case .fastest1K: return ATHLTHLocalization.choose(english: "Fastest 1 km", norwegian: "Raskeste 1 km")
        case .mostDistance: return ATHLTHLocalization.choose(english: "Most distance", norwegian: "Flest kilometer")
        case .mostWorkouts: return ATHLTHLocalization.choose(english: "Most workouts", norwegian: "Flest treningsøkter")
        case .mostRepetitions: return ATHLTHLocalization.choose(english: "Most repetitions", norwegian: "Flest repetisjoner")
        case .custom: return ATHLTHLocalization.choose(english: "Custom round", norwegian: "Egen runde")
        }
    }

    var explanation: String {
        switch self {
        case .fastest5K, .fastest1K:
            return ATHLTHLocalization.choose(
                english: "The fastest qualifying time wins.",
                norwegian: "Raskeste gyldige tid vinner."
            )
        case .mostDistance:
            return ATHLTHLocalization.choose(
                english: "Most qualifying distance during the round wins.",
                norwegian: "Flest gyldige kilometer i runden vinner."
            )
        case .mostWorkouts:
            return ATHLTHLocalization.choose(
                english: "Most qualifying workouts wins. Minimum length must be set before starting.",
                norwegian: "Flest godkjente økter vinner. Minste øktlengde må bestemmes før start."
            )
        case .mostRepetitions:
            return ATHLTHLocalization.choose(
                english: "Exercise and repetition requirements must be agreed before starting.",
                norwegian: "Øvelse og krav til repetisjoner må avtales før start."
            )
        case .custom:
            return ATHLTHLocalization.choose(
                english: "Agree on a measurable result and verification before starting.",
                norwegian: "Avtal et målbart resultat og verifisering før start."
            )
        }
    }
}

struct ATHLTHArenaRoundDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var template: ATHLTHArenaRoundTemplate
    var title: String
    var rules: String
}

struct ATHLTHArenaCompetitionDraft: Codable, Identifiable {
    var id = UUID()
    var ownerID: UUID
    var title: String
    var scope: ATHLTHArenaScope
    var scoring: ATHLTHArenaScoring
    var durationDays: Int
    var participantIDs: [UUID]
    var clubID: UUID?
    var createdAt = Date()
    var rounds: [ATHLTHArenaRoundDraft] = []
}

enum ATHLTHArenaDraftStorage {
    private static func key(for userID: UUID) -> String {
        AccountLocalStorage.key("arenaDrafts", userID: userID)
    }

    static func load(for userID: UUID) -> [ATHLTHArenaCompetitionDraft] {
        guard let data = UserDefaults.standard.data(forKey: key(for: userID)),
              let decoded = try? JSONDecoder().decode(
                [ATHLTHArenaCompetitionDraft].self,
                from: data
              ) else {
            return []
        }
        return decoded.filter { $0.ownerID == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ drafts: [ATHLTHArenaCompetitionDraft], for userID: UUID) {
        guard let encoded = try? JSONEncoder().encode(
            drafts.filter { $0.ownerID == userID }
        ) else { return }
        UserDefaults.standard.set(encoded, forKey: key(for: userID))
    }

    static func removeForDeletedAccount(_ userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userID))
    }
}

// MARK: - Community entry point

struct ATHLTHArenaEntryCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(ATHLTHTheme.accentDeep.opacity(0.09))
                    .frame(width: 58, height: 58)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ATHLTH Arena")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(ATHLTHLocalization.choose(
                    english: "Multiple rounds. One overall champion.",
                    norwegian: "Flere runder. Én sammenlagtvinner."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 3)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(16)
        .background(ATHLTHArenaLightStyle.card(23))
    }
}

private enum ATHLTHArenaCreationMode: String, Identifiable {
    case challenge
    case route
    case distance
    case strength
    case series

    var id: String { rawValue }
}

struct ATHLTHArenaHomeView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    @State private var drafts: [ATHLTHArenaCompetitionDraft] = []
    @State private var creationMode: ATHLTHArenaCreationMode?
    @State private var pendingDelete: UUID?
    @State private var remoteRevision = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introduction
                quickStart

                ATHLTHArenaOnlineSection()
                    .id(remoteRevision)

                HStack(spacing: 10) {
                    NavigationLink {
                        ATHLTHArenaSingleChallengesView()
                    } label: {
                        arenaDestination(
                            title: ATHLTHLocalization.choose(
                                english: "Challenges",
                                norwegian: "Enkeltutfordringer"
                            ),
                            detail: ATHLTHLocalization.choose(
                                english: "Invites, duels & results",
                                norwegian: "Dueller, invitasjoner og resultater"
                            ),
                            icon: "flag.checkered"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CommunityGroupsView()
                    } label: {
                        arenaDestination(
                            title: "Clubs",
                            detail: ATHLTHLocalization.choose(
                                english: "Group competitions",
                                norwegian: "Klubbkonkurranser"
                            ),
                            icon: "person.3.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Your competition series",
                        norwegian: "Dine konkurranseserier"
                    ))
                    .font(.headline)
                    Spacer()
                    Text("\(drafts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if drafts.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No series yet",
                            norwegian: "Ingen konkurranseserier ennå"
                        ),
                        systemImage: "trophy",
                        description: Text(ATHLTHLocalization.choose(
                            english: "Create a draft and suggest the first rounds.",
                            norwegian: "Opprett et utkast og foreslå de første rundene."
                        ))
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(drafts) { draft in
                        HStack(spacing: 10) {
                            NavigationLink {
                                ATHLTHArenaDraftDetailView(
                                    draft: draft,
                                    onSave: upsert,
                                    onPublished: { id in
                                        drafts.removeAll { $0.id == id }
                                        ATHLTHArenaDraftStorage.save(
                                            drafts,
                                            for: session.profile.userID
                                        )
                                        remoteRevision = UUID()
                                    }
                                )
                            } label: {
                                draftRow(draft)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                pendingDelete = draft.id
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .frame(width: 35, height: 44)
                            }
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Delete draft",
                                norwegian: "Slett utkast"
                            ))
                        }
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Drafts stay on this device until you publish. Publishing sends invitations and opens a shared lobby. Results are approved by the participants.",
                    norwegian: "Utkast lagres på denne enheten til du publiserer. Publisering sender invitasjoner og åpner en felles lobby. Resultatene godkjennes av deltakerne."
                ))
                .font(.footnote)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle("Arena")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.profile.userID) {
            drafts = ATHLTHArenaDraftStorage.load(for: session.profile.userID)
        }
        .sheet(item: $creationMode) { mode in
            switch mode {
            case .challenge:
                ChallengeCreationView()
            case .route:
                ATHLTHArenaRouteStarter()
            case .distance:
                ATHLTHArenaDistanceStarter()
            case .strength:
                ChallengeCreationView(preselectedSport: .strength)
            case .series:
                ATHLTHArenaCreateView(
                    ownerID: session.profile.userID,
                    friends: social.mutualFollows,
                    onCreate: upsert
                )
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Delete this draft?",
                norwegian: "Slette dette utkastet?"
            ),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button(
                ATHLTHLocalization.choose(english: "Delete", norwegian: "Slett"),
                role: .destructive
            ) {
                if let id = pendingDelete {
                    drafts.removeAll { $0.id == id }
                    ATHLTHArenaDraftStorage.save(drafts, for: session.profile.userID)
                }
                pendingDelete = nil
            }
            Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt"), role: .cancel) {
                pendingDelete = nil
            }
        }
    }

    private func arenaDestination(
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentDeep.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(.horizontal, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 0.8)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("ATHLTH ARENA", systemImage: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                Spacer()
                Text("2.0")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.13), in: Capsule())
            }
            .foregroundStyle(.white.opacity(0.88))

            Text(ATHLTHLocalization.choose(
                english: "Make every session a challenge.",
                norwegian: "Gjør hver økt til en utfordring."
            ))
            .font(.system(size: 29, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)

            Text(ATHLTHLocalization.choose(
                english: "Build routes, challenge friends and compete across multiple rounds.",
                norwegian: "Lag ruter, utfordre venner og konkurrer over flere runder."
            ))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.84))
            .fixedSize(horizontal: false, vertical: true)

            Button {
                creationMode = .challenge
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                    Text(ATHLTHLocalization.choose(
                        english: "New challenge",
                        norwegian: "Ny utfordring"
                    ))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [ATHLTHTheme.accentDeep, ATHLTHTheme.vitality],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Choose your competition",
                    norwegian: "Velg konkurranse"
                ))
                .font(.headline)
                Spacer()
                Text(ATHLTHLocalization.choose(english: "Quick start", norwegian: "Hurtigstart"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { creationMode = .route } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Route", norwegian: "Rute"),
                        detail: ATHLTHLocalization.choose(english: "Choose or create a route", norwegian: "Velg eller lag en rute"),
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                Button { creationMode = .distance } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                        detail: ATHLTHLocalization.choose(english: "Set your own length", norwegian: "Velg din egen lengde"),
                        icon: "timer"
                    )
                }
                Button { creationMode = .strength } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                        detail: ATHLTHLocalization.choose(english: "Weight, reps or volume", norwegian: "Vekt, reps eller volum"),
                        icon: "dumbbell.fill"
                    )
                }
                Button { creationMode = .series } label: {
                    quickStartCard(
                        title: ATHLTHLocalization.choose(english: "Competition series", norwegian: "Konkurranseserie"),
                        detail: ATHLTHLocalization.choose(english: "Multiple rounds and points", norwegian: "Flere runder og poeng"),
                        icon: "trophy.fill"
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func quickStartCard(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 37, height: 37)
                    .background(ATHLTHTheme.vitalitySoft.opacity(0.68), in: Circle())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(13)
        .background(ATHLTHArenaLightStyle.card(19))
        .accessibilityElement(children: .combine)
    }

    private func draftRow(_ draft: ATHLTHArenaCompetitionDraft) -> some View {
        HStack(spacing: 12) {
            Image(systemName: draft.scope.symbol)
                .font(.title3)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 42, height: 42)
                .background(ATHLTHTheme.accentDeep.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text("\(draft.scope.title) · \(draft.rounds.count) " +
                     ATHLTHLocalization.choose(english: "rounds", norwegian: "runder"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer(minLength: 3)
            Text(ATHLTHLocalization.choose(english: "Draft", norwegian: "Utkast"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
        }
        .padding(12)
        .background(.regularMaterial, in:
            RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func upsert(_ draft: ATHLTHArenaCompetitionDraft) {
        guard draft.ownerID == session.profile.userID else { return }
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(draft, at: 0)
        ATHLTHArenaDraftStorage.save(drafts, for: session.profile.userID)
    }
}

// MARK: - Creating a series

/// Reuses the established Challenge engine, including invitations and GPS rules.
private struct ATHLTHArenaRouteStarter: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoute: TrainingRoute?
    @State private var showingChallenge = false

    var body: some View {
        NavigationStack {
            SavedRoutesView(
                selectionTitle: ATHLTHLocalization.choose(
                    english: "Choose a competition route",
                    norwegian: "Velg konkurranserute"
                ),
                onSelect: { route in
                    selectedRoute = route
                    showingChallenge = true
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingChallenge) {
            if let selectedRoute {
                ChallengeCreationView(preselectedRouteID: selectedRoute.id)
            }
        }
    }
}

/// Only configures the requested distance; Challenge owns scoring and validation.
private struct ATHLTHArenaDistanceStarter: View {
    @Environment(\.dismiss) private var dismiss
    @State private var distanceText = "5"
    @State private var showingChallenge = false

    private var distanceKilometers: Double? {
        guard let distance = Double(
            distanceText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ), distance.isFinite, (0.1...500).contains(distance) else {
            return nil
        }
        return distance
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Choose any distance",
                        norwegian: "Bestem distansen selv"
                    ),
                    systemImage: "figure.run"
                )
                .font(.title2.weight(.bold))

                Text(ATHLTHLocalization.choose(
                    english: "Compete on any route over the chosen distance.",
                    norwegian: "Konkurrer hvor som helst på distansen du bestemmer."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)

                HStack(spacing: 8) {
                    ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { km in
                        Button("\(Int(km)) km") {
                            distanceText = String(Int(km))
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)
                    }
                }

                HStack(spacing: 10) {
                    TextField(
                        ATHLTHLocalization.choose(english: "Kilometers", norwegian: "Kilometer"),
                        text: $distanceText
                    )
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .padding(13)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    Text("km")
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                if distanceKilometers == nil {
                    Text(ATHLTHLocalization.choose(
                        english: "Enter a distance between 0.1 and 500 km.",
                        norwegian: "Angi en distanse fra 0,1 til 500 km."
                    ))
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                Button {
                    showingChallenge = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Continue to challenge",
                            norwegian: "Fortsett til utfordring"
                        ),
                        systemImage: "arrow.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .disabled(distanceKilometers == nil)
                Spacer()
            }
            .padding(20)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Distance challenge", norwegian: "Distanseutfordring"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingChallenge) {
            if let distanceKilometers {
                ChallengeCreationView(preselectedDistanceKm: distanceKilometers)
            }
        }
    }
}

struct ATHLTHArenaCreateView: View {
    @Environment(\.dismiss) private var dismiss

    let ownerID: UUID
    let friends: [SocialProfileCard]
    let onCreate: (ATHLTHArenaCompetitionDraft) -> Void

    @State private var title = ""
    @State private var scope: ATHLTHArenaScope = .duel
    @State private var scoring: ATHLTHArenaScoring = .winner
    @State private var durationDays = 14
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var clubChoices: [ATHLTHArenaClubChoice] = []
    @State private var selectedClubID: UUID?
    @State private var clubAthletes: [ATHLTHArenaClubAthlete] = []
    @State private var clubError: String?
    private let clubDirectory = ATHLTHArenaClubDirectory()

    init(
        ownerID: UUID,
        friends: [SocialProfileCard],
        preselectedFriendID: UUID? = nil,
        onCreate: @escaping (ATHLTHArenaCompetitionDraft) -> Void
    ) {
        self.ownerID = ownerID
        self.friends = friends
        self.onCreate = onCreate
        _selectedFriendIDs = State(initialValue:
            preselectedFriendID.map { Set([$0]) } ?? []
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Competition name",
                            norwegian: "Navn på konkurransen"
                        ),
                        text: $title
                    )
                    .textInputAutocapitalization(.sentences)
                    Picker(ATHLTHLocalization.choose(
                        english: "Format", norwegian: "Konkurranseform"
                    ), selection: $scope) {
                        ForEach(ATHLTHArenaScope.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    Picker(ATHLTHLocalization.choose(
                        english: "Scoring", norwegian: "Poengsystem"
                    ), selection: $scoring) {
                        ForEach(ATHLTHArenaScoring.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker(ATHLTHLocalization.choose(
                        english: "Duration", norwegian: "Varighet"
                    ), selection: $durationDays) {
                        ForEach([7, 14, 30], id: \.self) { days in
                            Text("\(days) " +
                                 ATHLTHLocalization.choose(english: "days", norwegian: "dager"))
                                .tag(days)
                        }
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Competition", norwegian: "Konkurranse"
                    ))
                }

                if scope == .club {
                    Section {
                        if clubChoices.isEmpty {
                            Text(ATHLTHLocalization.choose(
                                english: "Club admins can publish Club Arena series.",
                                norwegian: "Klubbadministratorer kan publisere Arena-serier for klubben."
                            ))
                            .foregroundStyle(.secondary)
                        }
                        ForEach(clubChoices) { choice in
                            Button {
                                selectedClubID = choice.id
                                selectedFriendIDs.removeAll()
                                Task { await loadClubAthletes(choice.id) }
                            } label: {
                                HStack {
                                    Text(choice.name).foregroundStyle(ATHLTHTheme.primaryText)
                                    Spacer()
                                    Image(systemName: selectedClubID == choice.id
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                            }
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose Club", norwegian: "Velg klubb"
                        ))
                    }
                    Section {
                        if selectedClubID == nil {
                            Text(ATHLTHLocalization.choose(
                                english: "Select a Club to see members.",
                                norwegian: "Velg en klubb for å se medlemmer."
                            )).foregroundStyle(.secondary)
                        }
                        Text("\(selectedFriendIDs.count)/20 " +
                            ATHLTHLocalization.choose(
                                english: "selected", norwegian: "valgt"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(clubAthletes) { athlete in
                            Button {
                                if selectedFriendIDs.contains(athlete.id) {
                                    selectedFriendIDs.remove(athlete.id)
                                } else if selectedFriendIDs.count < 20 {
                                    selectedFriendIDs.insert(athlete.id)
                                }
                            } label: {
                                HStack {
                                    Text(athlete.displayName)
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                    Spacer()
                                    Image(systemName: selectedFriendIDs.contains(athlete.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                            }
                        }
                        if let clubError {
                            Text(clubError).font(.caption).foregroundStyle(.red)
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Club athletes", norwegian: "Klubbmedlemmer"
                        ))
                    } footer: {
                        Text(ATHLTHLocalization.choose(
                            english: "Select up to 20 members; Inbox invitations are sent on publishing.",
                            norwegian: "Velg opptil 20 medlemmer. Invitasjoner sendes via innboksen ved publisering."
                        ))
                    }
                } else {
                    Section {
                        if friends.isEmpty {
                            Text(ATHLTHLocalization.choose(
                                english: "Mutual followers will appear here. You can still save a draft now.",
                                norwegian: "Gjensidige følgere vises her. Du kan likevel lagre et utkast nå."
                            ))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(friends, id: \.userID) { friend in
                                Button {
                                    if scope == .duel {
                                        selectedFriendIDs = [friend.userID]
                                    } else if !selectedFriendIDs.insert(friend.userID).inserted {
                                        selectedFriendIDs.remove(friend.userID)
                                    }
                                } label: {
                                    HStack {
                                        Text(friend.resolvedName)
                                            .foregroundStyle(ATHLTHTheme.primaryText)
                                        Spacer()
                                        Image(systemName:
                                            selectedFriendIDs.contains(friend.userID)
                                            ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(
                            english: "Invitees (draft only)",
                            norwegian: "Deltakere (kun utkast)"
                        ))
                    } footer: {
                        Text(scope == .club
                            ? ATHLTHLocalization.choose(
                                english: "Club membership and invitations will be connected in the next phase.",
                                norwegian: "Club-medlemskap og invitasjoner kobles på i neste fase."
                              )
                            : ATHLTHLocalization.choose(
                                english: "Selecting someone here does not send an invitation.",
                                norwegian: "Å velge noen her sender ikke en invitasjon."
                              ))
                    }
    
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "New series", norwegian: "Ny konkurranseserie"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Create draft", norwegian: "Opprett utkast")) {
                        let draft = ATHLTHArenaCompetitionDraft(
                            ownerID: ownerID,
                            title: String(title.trimmingCharacters(
                                in: .whitespacesAndNewlines).prefix(80)),
                            scope: scope,
                            scoring: scoring,
                            durationDays: durationDays,
                            participantIDs: Array(selectedFriendIDs).sorted {
                                $0.uuidString < $1.uuidString
                            },
                            clubID: scope == .club ? selectedClubID : nil
                        )
                        onCreate(draft)
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (scope == .club && selectedClubID == nil)
                    )
                }
            }
            .task { await loadClubs() }
            .onChange(of: scope) { _, next in
                selectedFriendIDs.removeAll()
                if next != .club {
                    selectedClubID = nil
                    clubAthletes = []
                }
            }
        }
        .environment(\.colorScheme, .light)
        .tint(ATHLTHArenaLightStyle.action)
    }

    @MainActor
    private func loadClubs() async {
        do {
            clubChoices = try await clubDirectory.manageableClubs()
            clubError = nil
        } catch {
            clubError = error.localizedDescription
        }
    }

    @MainActor
    private func loadClubAthletes(_ club: UUID) async {
        do {
            let loaded = try await clubDirectory.athletes(in: club)
            guard selectedClubID == club else { return }
            clubAthletes = loaded
            clubError = nil
        } catch {
            clubError = error.localizedDescription
        }
    }
}

// MARK: - Editing a competition draft and its proposed rounds

struct ATHLTHArenaDraftDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ATHLTHArenaCompetitionDraft
    @State private var showingAddRound = false

    let onSave: (ATHLTHArenaCompetitionDraft) -> Void
    let onPublished: (UUID) -> Void

    @State private var publishing = false
    @State private var publishError: String?

    init(
        draft: ATHLTHArenaCompetitionDraft,
        onSave: @escaping (ATHLTHArenaCompetitionDraft) -> Void,
        onPublished: @escaping (UUID) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onPublished = onPublished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Competition draft",
                            norwegian: "Konkurranseutkast"
                        ),
                        systemImage: "trophy.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                    Text(draft.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text("\(draft.scope.title) · \(draft.durationDays) " +
                         ATHLTHLocalization.choose(english: "days", norwegian: "dager"))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Text(draft.scoring.title)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.regularMaterial, in:
                    RoundedRectangle(cornerRadius: 22))

                HStack {
                    Text(ATHLTHLocalization.choose(english: "Rounds", norwegian: "Runder"))
                        .font(.headline)
                    Spacer()
                    Text("\(draft.rounds.count)")
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if draft.rounds.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Add the first round. All rules can be revised before invitations are enabled.",
                        norwegian: "Legg til den første runden. Reglene kan endres før invitasjoner aktiveres."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .padding(16)
                }

                ForEach(draft.rounds) { round in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\((draft.rounds.firstIndex(where: { $0.id == round.id }) ?? 0) + 1)")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 27)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(round.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(round.rules)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer(minLength: 3)
                        Button(role: .destructive) {
                            draft.rounds.removeAll { $0.id == round.id }
                            onSave(draft)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Remove round", norwegian: "Fjern runde"
                        ))
                    }
                    .padding(14)
                    .background(.regularMaterial, in:
                        RoundedRectangle(cornerRadius: 17))
                }

                Button {
                    showingAddRound = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Add round", norwegian: "Legg til runde"
                    ), systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)

                VStack(alignment: .leading, spacing: 9) {
                    if draft.scope == .club && draft.clubID == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose a Club when creating a new draft.",
                            norwegian: "Velg en klubb når du oppretter et nytt utkast."
                        ))
                        .font(.footnote)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        Button {
                            Task { await publishDraft() }
                        } label: {
                            HStack {
                                if publishing {
                                    ProgressView().tint(.white)
                                }
                                Label(ATHLTHLocalization.choose(
                                    english: "Send invitations",
                                    norwegian: "Send invitasjoner"
                                ), systemImage: "paperplane.fill")
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accentDeep)
                        .disabled(
                            publishing ||
                            draft.participantIDs.isEmpty ||
                            draft.rounds.isEmpty
                        )
                    }

                    if let publishError {
                        Text(publishError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "A published series becomes a shared, pre-start lobby. It does not automatically begin a competition.",
                        norwegian: "En publisert serie blir et delt lobby-utkast. Konkurransen starter ikke automatisk."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label(ATHLTHLocalization.choose(
                        english: "Not started",
                        norwegian: "Ikke startet"
                    ), systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "These are private drafts. Publishing sends Inbox invitations and opens a shared Arena lobby. Points require participant approval.",
                        norwegian: "Dette er private utkast. Publisering sender invitasjoner via innboksen og åpner en felles Arena-lobby. Poeng krever deltakernes godkjenning."
                    ))
                    .font(.footnote)
                }
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHTheme.accentDeep.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 17))
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Competition series", norwegian: "Konkurranseserie"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddRound) {
            ATHLTHArenaAddRoundView { round in
                draft.rounds.append(round)
                onSave(draft)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                    onSave(draft)
                    dismiss()
                }
            }
        }
    }

    @MainActor
    private func publishDraft() async {
        guard !publishing else { return }
        publishing = true
        publishError = nil
        defer { publishing = false }

        do {
            _ = try await ATHLTHArenaCloudService().publish(draft)
            onPublished(draft.id)
            dismiss()
        } catch {
            publishError = error.localizedDescription
        }
    }
}

struct ATHLTHArenaAddRoundView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (ATHLTHArenaRoundDraft) -> Void

    @State private var template: ATHLTHArenaRoundTemplate = .fastest5K
    @State private var title = ATHLTHArenaRoundTemplate.fastest5K.title
    @State private var rules = ATHLTHArenaRoundTemplate.fastest5K.explanation
    @State private var exerciseName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(ATHLTHLocalization.choose(
                        english: "Round type", norwegian: "Type utfordring"
                    ), selection: $template) {
                        ForEach(ATHLTHArenaRoundTemplate.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    TextField(ATHLTHLocalization.choose(
                        english: "Round name", norwegian: "Navn på runden"
                    ), text: $title)
                    if template == .mostRepetitions {
                        TextField(ATHLTHLocalization.choose(
                            english: "Exercise to compete in (required)",
                            norwegian: "Øvelsen dere konkurrerer i (påkrevd)"
                        ), text: $exerciseName)
                    }
                    TextField(ATHLTHLocalization.choose(
                        english: "Rules and verification",
                        norwegian: "Regler og verifisering"
                    ), text: $rules, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "The scoring and verification rules must be accepted by participants before a round goes live.",
                        norwegian: "Regler for poeng og verifisering må godkjennes av deltakerne før runden starter."
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHArenaLightStyle.canvasBackground)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "New round", norwegian: "Ny runde"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: template) { _, newValue in
                title = newValue.title
                rules = newValue.explanation
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Add", norwegian: "Legg til")) {
                        onAdd(ATHLTHArenaRoundDraft(
                            template: template,
                            title: String(title.trimmingCharacters(
                                in: .whitespacesAndNewlines).prefix(80)),
                            rules: String((
                                (template == .mostRepetitions
                                    ? "Øvelse: " + exerciseName.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                      ) + "\n"
                                    : "") +
                                rules.trimmingCharacters(in: .whitespacesAndNewlines)
                            ).prefix(600))
                        ))
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (template == .mostRepetitions &&
                         exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        .environment(\.colorScheme, .light)
        .tint(ATHLTHArenaLightStyle.action)
        }
    }
}


// MARK: - Existing competitive Challenges in Arena
// Official Weekly Challenge keeps its independent editorial/admin workflows.
struct ATHLTHArenaSingleChallengesView: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var session: AppSessionStore
    @State private var showingCreate = false

    private var invitations: [ATHLTHChallenge] {
        challenges.incomingInvitations(for: session.profile.userID)
    }

    private var activeChallenges: [ATHLTHChallenge] {
        challenges.trainingChallenges(for: session.profile.userID)
    }

    private var history: [ATHLTHChallenge] {
        challenges.visibleChallenges
            .filter { $0.status == .completed || $0.status == .cancelled }
            .filter {
                $0.creatorID == session.profile.userID ||
                $0.participants.contains { $0.userID == session.profile.userID }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Single challenges",
                        norwegian: "Enkeltutfordringer"
                    ))
                    .font(.title2.weight(.bold))
                    Text(ATHLTHLocalization.choose(
                        english: "One-off duels, routes and activity goals. Series are managed separately in Arena.",
                        norwegian: "Enkeltdueller, ruter og aktivitetsmål. Konkurranseserier administreres separat i Arena."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Button {
                        showingCreate = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "New challenge", norwegian: "Ny utfordring"
                        ), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                }
                .padding(17)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 22))

                challengeSection(
                    ATHLTHLocalization.choose(english: "Invitations", norwegian: "Invitasjoner"),
                    items: invitations
                )
                challengeSection(
                    ATHLTHLocalization.choose(english: "Active challenges", norwegian: "Aktive utfordringer"),
                    items: activeChallenges
                )
                challengeSection(
                    ATHLTHLocalization.choose(english: "History", norwegian: "Historikk"),
                    items: history
                )
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHArenaLightStyle.canvasBackground)
        .environment(\.colorScheme, .light)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Challenges", norwegian: "Utfordringer"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreate) {
            ChallengeCreationView()
        }
    }

    private func challengeSection(
        _ heading: String,
        items: [ATHLTHChallenge]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(heading)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)
            if items.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Nothing here yet.",
                    norwegian: "Ingenting her ennå."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 17))
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        ChallengeDetailView(challengeID: item.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.sport.systemImage)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(item.sport.title)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .padding(14)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
