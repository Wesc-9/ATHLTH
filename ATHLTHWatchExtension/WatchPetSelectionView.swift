import SwiftUI

/// Watch stores only names and IDs; all personal pet details stay on iPhone.
struct WatchPetSelectionButton: View {
    @EnvironmentObject private var routeStore: WatchRouteStore

    var body: some View {
        if !routeStore.petCatalog.isEmpty {
            NavigationLink {
                WatchPetSelectionView()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(WatchTheme.planAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ATHLTHLocalization.choose(
                            english: "My companions", norwegian: "Mine turkamerater"))
                            .font(.system(size: 11, weight: .semibold))
                        let selected = routeStore.selectedPetIDs.count
                        Text(selected == 0
                             ? ATHLTHLocalization.choose(
                                 english: "Choose pets", norwegian: "Velg kjæledyr")
                             : "\(selected) " + ATHLTHLocalization.choose(
                                 english: "selected", norwegian: "valgt"))
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.planSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchTheme.planSecondary)
                }
                .padding(10)
                .watchSurface(radius: 13)
            }
            .buttonStyle(.plain)
        }
    }
}

struct WatchPetSelectionView: View {
    @EnvironmentObject private var routeStore: WatchRouteStore
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(ATHLTHLocalization.choose(
                    english: "Who is joining?", norwegian: "Hvem blir med?"))
                    .font(.headline)
                Text(ATHLTHLocalization.choose(
                    english: "Select your companions before or during a workout.",
                    norwegian: "Velg turkamerater før eller under økten."))
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.planSecondary)
                ForEach(routeStore.petCatalog) { pet in
                    Button {
                        var selection = routeStore.selectedPetIDs
                        if selection.contains(pet.id) {
                            selection.remove(pet.id)
                        } else {
                            selection.insert(pet.id)
                        }
                        routeStore.setSelectedPetIDs(
                            selection,
                            distanceMeters: workoutManager.isActive
                                ? workoutManager.distanceMeters : nil)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "pawprint")
                                .foregroundStyle(WatchTheme.planAccent)
                            Text(pet.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: routeStore.selectedPetIDs.contains(pet.id)
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(routeStore.selectedPetIDs.contains(pet.id)
                                    ? WatchTheme.planAccent : WatchTheme.planSecondary)
                        }
                        .padding(11)
                        .watchSurface(radius: 13)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(routeStore.selectedPetIDs.contains(pet.id)
                        ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.planCanvas.ignoresSafeArea())
        .foregroundStyle(WatchTheme.planInk)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Companions", norwegian: "Turkamerater"))
    }
}
