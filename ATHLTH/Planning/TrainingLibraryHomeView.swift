import SwiftUI

struct TrainingLibraryHomeView: View {
    let onStartRunning: (RunningWorkoutTemplate) -> Void

    var body: some View {
        VStack(spacing: 20) {
            librarySection("Exercises", subtitle: "Find your next exercise or build your own.") {
                NavigationLink {
                    ExerciseLibraryView(source: .library)
                } label: {
                    LibraryDestinationTile(title: "Database", subtitle: "Muscles & equipment", icon: "dumbbell.fill")
                }
                NavigationLink {
                    ExerciseLibraryView(source: .mine)
                } label: {
                    LibraryDestinationTile(title: "My Exercises", subtitle: "Created by you", icon: "person.crop.square")
                }
            }

            librarySection("Running", subtitle: "Structured sessions for your next run.") {
                NavigationLink {
                    RunningWorkoutLibraryView(source: .library, onStart: onStartRunning)
                } label: {
                    LibraryDestinationTile(title: "Database", subtitle: "Intervals, tempo & more", icon: "figure.run")
                }
                NavigationLink {
                    RunningWorkoutLibraryView(source: .mine, onStart: onStartRunning)
                } label: {
                    LibraryDestinationTile(title: "My Workouts", subtitle: "Your running sessions", icon: "stopwatch")
                }
            }

            librarySection("Routes", subtitle: "Explore somewhere new or return to a favourite.") {
                NavigationLink {
                    RouteLibraryListView(source: .database)
                } label: {
                    LibraryDestinationTile(title: "Database", subtitle: "Discover & sort routes", icon: "globe.europe.africa.fill")
                }
                NavigationLink {
                    RouteLibraryListView(source: .mine)
                } label: {
                    LibraryDestinationTile(title: "My Routes", subtitle: "Saved & created by you", icon: "map.fill")
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
                Text(title).font(.title3.weight(.bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
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
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHTheme.accent.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}
