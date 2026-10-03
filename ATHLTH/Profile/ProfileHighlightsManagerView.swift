import SwiftUI

enum ProfileMomentFavorites {
    static let storageKey =
        "athlth.profile.favoriteMoments.v1"

    static func mediaToken(
        _ id: UUID
    ) -> String {
        "media:\(id.uuidString)"
    }

    static func highlightToken(
        _ id: UUID
    ) -> String {
        "highlight:\(id.uuidString)"
    }

    static func decode(
        _ raw: String
    ) -> Set<String> {
        Set(
            raw
                .split(separator: ",")
                .map(String.init)
        )
    }

    static func encode(
        _ values: Set<String>
    ) -> String {
        values
            .sorted()
            .joined(separator: ",")
    }
}

struct ProfileHighlightsManagerView: View {
    @EnvironmentObject private var social:
        SocialStore
    @EnvironmentObject private var health:
        HealthKitManager

    @AppStorage(ProfileMomentFavorites.storageKey)
    private var favoriteMomentSelectionRaw = ""

    private var favoriteTokens:
        Set<String> {
        ProfileMomentFavorites.decode(
            favoriteMomentSelectionRaw
        )
    }

    private var media:
        [WorkoutMediaRecord] {
        social.workoutMedia
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    private var workouts:
        [WorkoutSummary] {
        health.workouts
            .sorted {
                $0.startDate >
                    $1.startDate
            }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.18)
            )

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    introCard

                    if media.isEmpty &&
                        workouts.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "No workout moments yet",
                                norwegian:
                                    "Ingen øyeblikk ennå"
                            ),
                            systemImage:
                                "photo.on.rectangle.angled",
                            description:
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Photos added after workouts and completed workout highlights will appear here.",
                                        norwegian:
                                            "Bilder du legger til etter økter og høydepunkter fra fullførte økter vises her."
                                    )
                                )
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .padding(.top, 24)
                    } else {
                        if !media.isEmpty {
                            momentSectionHeader(
                                title:
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Photos",
                                        norwegian:
                                            "Bilder"
                                    ),
                                icon:
                                    "photo.fill"
                            )

                            LazyVStack(
                                spacing: 9
                            ) {
                                ForEach(
                                    media
                                ) { item in
                                    mediaRow(
                                        item
                                    )
                                }
                            }
                        }

                        if !workouts.isEmpty {
                            momentSectionHeader(
                                title:
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Workout highlights",
                                        norwegian:
                                            "Høydepunkter"
                                    ),
                                icon:
                                    "sparkles"
                            )
                            .padding(.top, 2)

                            LazyVStack(
                                spacing: 9
                            ) {
                                ForEach(
                                    workouts
                                ) { workout in
                                    highlightRow(
                                        workout
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 80)
                .frame(maxWidth: 720)
                .frame(
                    maxWidth: .infinity
                )
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Photos & highlights",
                norwegian:
                    "Bilder og høydepunkter"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task {
            await social
                .refreshWorkoutMedia()
        }
    }

    private var introCard:
        some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(
                systemName:
                    "star.circle.fill"
            )
            .font(.title2)
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Choose what appears on your profile",
                        norwegian:
                            "Velg hva som vises på profilen"
                    )
                )
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Tap the star on a photo or workout highlight. Only favorites are shown in the profile section.",
                        norwegian:
                            "Trykk på stjernen på et bilde eller høydepunkt. Bare favoritter vises i profilseksjonen."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer(
                minLength: 0
            )
        }
        .padding(14)
        .background(
            Color.white.opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.12),
                lineWidth: 0.8
            )
        }
    }

    private func momentSectionHeader(
        title: String,
        icon: String
    ) -> some View {
        Label(
            title,
            systemImage: icon
        )
        .font(
            .headline.weight(
                .bold
            )
        )
        .foregroundStyle(
            ATHLTHTheme
                .primaryText
        )
        .padding(
            .horizontal,
            2
        )
    }

    private func mediaRow(
        _ item:
            WorkoutMediaRecord
    ) -> some View {
        let token =
            ProfileMomentFavorites
                .mediaToken(item.id)
        let selected =
            favoriteTokens
                .contains(token)

        return Button {
            toggle(token)
        } label: {
            HStack(
                spacing: 12
            ) {
                AsyncImage(
                    url:
                        URL(
                            string:
                                item.imageURL
                        )
                ) { phase in
                    switch phase {
                    case .success(
                        let image
                    ):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(
                                ATHLTHTheme
                                    .surfaceSage
                            )
                            .overlay {
                                Image(
                                    systemName:
                                        "photo"
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }
                    }
                }
                .frame(
                    width: 64,
                    height: 64
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style:
                            .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        item.caption?
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .nilIfEmpty ??
                        ATHLTHLocalization.choose(
                            english:
                                "Workout photo",
                            norwegian:
                                "Treningsbilde"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(2)

                    Text(
                        item.createdAt
                            .formatted(
                                date:
                                    .abbreviated,
                                time:
                                    .omitted
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer(
                    minLength: 0
                )

                favoriteIcon(
                    selected
                )
            }
            .padding(10)
            .background(
                Color.white.opacity(
                    0.88
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    selected
                        ? ATHLTHTheme
                            .premiumGold
                            .opacity(0.24)
                        : Color.black
                            .opacity(0.04),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func highlightRow(
        _ workout:
            WorkoutSummary
    ) -> some View {
        let token =
            ProfileMomentFavorites
                .highlightToken(
                    workout.id
                )
        let selected =
            favoriteTokens
                .contains(token)

        return Button {
            toggle(token)
        } label: {
            HStack(
                spacing: 12
            ) {
                Image(
                    systemName:
                        workout.activity
                            .icon
                )
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 44,
                    height: 44
                )
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 13,
                            style:
                                .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        workout.activity
                            .rawValue
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    HStack(
                        spacing: 6
                    ) {
                        Text(
                            highlightValue(
                                workout
                            )
                        )

                        Text("·")

                        Text(
                            workout.startDate
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .omitted
                                )
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer(
                    minLength: 0
                )

                favoriteIcon(
                    selected
                )
            }
            .padding(11)
            .background(
                Color.white.opacity(
                    0.88
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    selected
                        ? ATHLTHTheme
                            .premiumGold
                            .opacity(0.24)
                        : Color.black
                            .opacity(0.04),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func favoriteIcon(
        _ selected: Bool
    ) -> some View {
        Image(
            systemName:
                selected
                    ? "star.fill"
                    : "star"
        )
        .font(
            .system(
                size: 18,
                weight: .semibold
            )
        )
        .foregroundStyle(
            selected
                ? ATHLTHTheme
                    .premiumGold
                : ATHLTHTheme
                    .mutedText
                    .opacity(0.65)
        )
        .frame(
            width: 38,
            height: 38
        )
        .background(
            selected
                ? ATHLTHTheme
                    .premiumGold
                    .opacity(0.10)
                : Color.black
                    .opacity(0.025),
            in: Circle()
        )
    }

    private func highlightValue(
        _ workout:
            WorkoutSummary
    ) -> String {
        if let meters =
            workout.distanceMeters,
           meters > 0 {
            return String(
                format:
                    "%.1f km",
                meters / 1_000
            )
        }

        let minutes =
            max(
                Int(
                    (
                        workout.duration /
                        60
                    ).rounded()
                ),
                0
            )

        if minutes >= 60 {
            return
                "\(minutes / 60)t " +
                "\(minutes % 60)m"
        }

        return
            "\(minutes) min"
    }

    private func toggle(
        _ token: String
    ) {
        var updated =
            favoriteTokens

        if updated.contains(
            token
        ) {
            updated.remove(
                token
            )
        } else {
            updated.insert(
                token
            )
        }

        favoriteMomentSelectionRaw =
            ProfileMomentFavorites
                .encode(updated)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
