import SwiftUI

struct TrainingLibraryHomeView: View {
    @EnvironmentObject private var favorites: LibraryFavoritesStore

    let onStartRunning: (RunningWorkoutTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TRAINING LIBRARY")
                    .font(.caption2.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                Text("Find your next session")
                    .font(
                        .system(
                            size: 30,
                            weight: .bold,
                            design: .serif
                        )
                    )

                Text(
                    "Plans, workouts, exercises and routes — ready when you are."
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            librarySection(
                "Your Library",
                subtitle: "Keep the things you use most close at hand."
            ) {
                NavigationLink {
                    LibraryFavoritesView(
                        onStartRunning: onStartRunning
                    )
                } label: {
                    LibraryDestinationTile(
                        title: "Favorites",
                        subtitle:
                            favorites.favorites.isEmpty
                                ? "Save plans, workouts & more"
                                : "\(favorites.favorites.count) saved items",
                        icon: "star.fill",
                        tint: ATHLTHTheme.premiumGold
                    )
                }

                NavigationLink {
                    MyTrainingPlansLibraryView()
                } label: {
                    LibraryDestinationTile(
                        title: "My Plans",
                        subtitle: "Created, saved & scheduled",
                        icon: "calendar.badge.clock",
                        tint: ATHLTHTheme.accent
                    )
                }
            }

            librarySection(
                "Training Plans",
                subtitle: "Start from a proven structure or build your own."
            ) {
                NavigationLink {
                    TrainingPlanLibraryView()
                } label: {
                    LibraryDestinationTile(
                        title: "Plan Library",
                        subtitle: "Running, strength & hybrid",
                        icon: "square.stack.3d.up.fill",
                        tint: Color.orange
                    )
                }

                NavigationLink {
                    TrainingPlanCreationView()
                } label: {
                    LibraryDestinationTile(
                        title: "Create Plan",
                        subtitle: "Build it your way",
                        icon: "plus.rectangle.on.rectangle",
                        tint: ATHLTHTheme.accent
                    )
                }
            }

            librarySection(
                "Running",
                subtitle: "Intervals, tempo sessions and saved workouts."
            ) {
                NavigationLink {
                    RunningWorkoutLibraryView(
                        source: .library,
                        onStart: onStartRunning
                    )
                } label: {
                    LibraryDestinationTile(
                        title: "Run Library",
                        subtitle: "Intervals, tempo & more",
                        icon: "figure.run",
                        tint: ATHLTHTheme.vitality
                    )
                }

                NavigationLink {
                    RunningWorkoutLibraryView(
                        source: .mine,
                        onStart: onStartRunning
                    )
                } label: {
                    LibraryDestinationTile(
                        title: "My Workouts",
                        subtitle: "Saved running sessions",
                        icon: "stopwatch",
                        tint: ATHLTHTheme.vitality
                    )
                }
            }

            librarySection(
                "Strength",
                subtitle: "Build from the exercise database or your own movements."
            ) {
                NavigationLink {
                    ExerciseLibraryView(source: .library)
                } label: {
                    LibraryDestinationTile(
                        title: "Exercises",
                        subtitle: "Muscles & equipment",
                        icon: "dumbbell.fill",
                        tint: Color.indigo
                    )
                }

                NavigationLink {
                    ExerciseLibraryView(source: .mine)
                } label: {
                    LibraryDestinationTile(
                        title: "My Exercises",
                        subtitle: "Created by you",
                        icon: "person.crop.square",
                        tint: Color.indigo
                    )
                }
            }

            librarySection(
                "Routes",
                subtitle: "Discover a new route or return to a favourite."
            ) {
                NavigationLink {
                    RouteLibraryListView(source: .database)
                } label: {
                    LibraryDestinationTile(
                        title: "Explore Routes",
                        subtitle: "Discover & filter",
                        icon: "map.fill",
                        tint: Color.green
                    )
                }

                NavigationLink {
                    RouteLibraryListView(source: .mine)
                } label: {
                    LibraryDestinationTile(
                        title: "My Routes",
                        subtitle: "Saved & created by you",
                        icon: "bookmark.fill",
                        tint: Color.green
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            await favorites.refresh()
        }
    }

    private func librarySection<Content: View>(
        _ title: String, subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                content()
            }
        }
    }
}

private struct LibraryDestinationTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        tint.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHTheme.accent.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}
