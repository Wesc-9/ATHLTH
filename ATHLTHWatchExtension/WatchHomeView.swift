import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATHLTH")
                            .font(.headline.weight(.black))
                            .tracking(2)

                        Text(routeStore.connectionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Routes") {
                    if routeStore.routes.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("No routes yet", systemImage: "map")
                                .font(.headline)

                            Text("Send a route from ATHLTH on iPhone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(routeStore.routes) { route in
                            NavigationLink {
                                WatchRouteDetailView(route: route)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.title)
                                        .font(.headline)

                                    Text(String(format: "%.1f km", route.distanceKilometers))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("ATHLTH")
        }
    }
}
