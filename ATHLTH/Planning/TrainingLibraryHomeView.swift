import SwiftUI

struct TrainingLibraryHomeView: View {
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
                    "Workouts, exercises and routes — ready when you are."
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
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
