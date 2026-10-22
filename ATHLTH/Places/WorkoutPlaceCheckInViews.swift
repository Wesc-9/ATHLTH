@preconcurrency import CoreLocation
import MapKit
import SwiftUI

// Shared by the workout detail and its place picker.
private func placeTR(_ en: String, _ no: String) -> String {
    ATHLTHLocalization.choose(english: en, norwegian: no)
}

struct WorkoutPlaceCompactBadge: View {
    @EnvironmentObject private var places:
        WorkoutPlaceCheckInStore

    let workoutID: UUID

    var body: some View {
        Group {
            if places.record(
                for: workoutID
            ) != nil {
                HStack(spacing: 7) {
                    Image(
                        systemName:
                            "mappin.and.ellipse"
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    Text(placeLabel)
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                    Spacer()

                    Text(placeTR("Private", "Privat"))
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    ATHLTHTheme
                        .vitalitySoft
                        .opacity(0.72),
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
            }
        }
        .task(id: workoutID) {
            await places.refresh()

            if places.record(
                for: workoutID
            ) != nil {
                _ = await places.resolvePlace(
                    for: workoutID
                )
            }
        }
    }

    private var placeLabel: String {
        if let place =
            places.resolvedPlace(
                for: workoutID
            ) {
            return placeTR("Trained at \(place.name)", "Trent hos \(place.name)")
        }

        return placeTR("Training place", "Treningssted")
    }
}

struct WorkoutPlaceCheckInSection: View {
    @EnvironmentObject private var places:
        WorkoutPlaceCheckInStore

    let workoutID: UUID

    @State private var showingPicker = false
    @State private var resolving = false

    private var record:
        WorkoutPlaceCheckInRecord? {
        places.record(for: workoutID)
    }

    private var place:
        WorkoutPlacePresentation? {
        places.resolvedPlace(
            for: workoutID
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 13
        ) {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        "mappin.and.ellipse"
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(
                    width: 36,
                    height: 36
                )
                .background(
                    ATHLTHTheme
                        .vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(placeTR("Training place", "Treningssted"))
                        .font(
                            .headline.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        record == nil
                            ? placeTR("Add the training place for this workout.", "Legg til treningssted for denne økten.")
                            : placeTR("Saved privately to this workout.", "Lagret privat på denne økten.")
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            if let record {
                HStack(spacing: 11) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        if let place {
                            Text(place.name)
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

                            Text(
                                visitText(
                                    placeID:
                                        place.id
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        } else {
                            HStack(spacing: 7) {
                                if resolving {
                                    ProgressView()
                                        .controlSize(
                                            .small
                                        )
                                }

                                Text(
                                    resolving
                                        ? placeTR("Loading place…", "Laster treningssted…")
                                        : placeTR("Training place", "Treningssted")
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )
                            }
                        }

                        Text(
                            record.checkedInAt
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Button {
                        showingPicker = true
                    } label: {
                        Text(placeTR("Change", "Endre"))
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button(
                            placeTR("Remove place", "Fjern treningssted"),
                            role: .destructive
                        ) {
                            Task {
                                _ = await places
                                    .remove(
                                        workoutID:
                                            workoutID
                                    )
                            }
                        }
                    } label: {
                        Image(
                            systemName:
                                "ellipsis.circle"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                }
            } else {
                Button {
                    showingPicker = true
                } label: {
                    Label(
                        placeTR("Add training place", "Legg til treningssted"),
                        systemImage:
                            "plus.circle.fill"
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 42)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.accent
                )
            }

            Text(
                placeTR("ATHLTH stores the Apple Place ID, not a separate copy of the venue address. Place check-ins are private unless you explicitly choose to share them later.", "ATHLTH lagrer stedets Apple-ID, ikke en egen kopi av adressen. Innsjekkinger er private med mindre du velger å dele dem senere.")
            )
            .font(.caption2)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
        .padding(ATHLTHPlanDesign.Density.comfortable.cardPadding)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHPlanDesign.surface,
                    ATHLTHTheme.cardWarm.opacity(0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: ATHLTHPlanDesign.cardRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ATHLTHPlanDesign.cardRadius,
                style: .continuous
            )
            .stroke(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.055), radius: 13, y: 5)
        .sheet(
            isPresented:
                $showingPicker
        ) {
            WorkoutPlacePickerView(
                workoutID: workoutID
            )
        }
        .task(id: workoutID) {
            await places.refresh()

            guard record != nil,
                  place == nil
            else {
                return
            }

            resolving = true
            _ = await places.resolvePlace(
                for: workoutID
            )
            resolving = false
        }
    }

    private func visitText(
        placeID: String
    ) -> String {
        let count =
            places.visitCount(
                placeID: placeID
            )

        if count == 1 {
            return placeTR("First workout here", "Første økt her")
        }

        return ATHLTHLocalization.choose(
            english: "\(count) workouts here",
            norwegian: "\(count) økter her"
        )
    }
}

private struct WorkoutPlacePickerView:
    View {
    @EnvironmentObject private var places:
        WorkoutPlaceCheckInStore
    @EnvironmentObject private var session:
        AppSessionStore
    @Environment(\.dismiss)
    private var dismiss

    let workoutID: UUID

    @StateObject private var location =
        WorkoutPlaceLocationStore()

    @State private var nearby:
        [WorkoutPlacePresentation] = []
    @State private var frequent:
        [WorkoutPlacePresentation] = []
    @State private var loading = false
    @State private var savingPlaceID:
        String?
    @State private var errorMessage:
        String?
    @State private var lastSearchLocation: CLLocation?
    @State private var lastSearchAt: Date?
    @State private var forceNextSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    privacyBanner

                    if loading ||
                        location.isUpdating {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(
                                    .small
                                )

                            Text(
                                placeTR("Finding nearby training venues within 150 m…", "Søker etter treningssteder innen 150 m…")
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                        .frame(
                            maxWidth:
                                .infinity,
                            alignment:
                                .leading
                        )
                    }

                    if !frequent.isEmpty {
                        placeSection(
                            title:
                                placeTR("Places you train often", "Steder du trener ofte"),
                            icon:
                                "star.fill",
                            places:
                                frequent
                        )
                    }

                    placeSection(
                        title: placeTR("Nearby", "I nærheten"),
                        icon:
                            "location.fill",
                        places:
                            nearby
                    )

                    if !loading,
                       !location.isUpdating,
                       nearby.isEmpty {
                        ContentUnavailableView(
                            placeTR("No training venue within 150 m", "Ingen treningssteder innen 150 m"),
                            systemImage:
                                "figure.strengthtraining.traditional",
                            description:
                                Text(
                                    placeTR("Move closer to the venue and refresh. ATHLTH only allows a check-in when you're physically nearby.", "Gå nærmere treningsstedet og oppdater. ATHLTH tillater bare innsjekking når du er i nærheten.")
                                )
                        )
                        .frame(
                            minHeight: 220
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(
                                .red
                            )
                            .fixedSize(
                                horizontal:
                                    false,
                                vertical: true
                            )
                    }
                }
                .padding(16)
            }
            .background(
                ATHLTHPremiumCanvas()
            )
            .navigationTitle(
                placeTR("Training place", "Treningssted")
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(placeTR("Close", "Lukk")) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button {
                        forceNextSearch = true
                        location.refresh()
                    } label: {
                        Image(
                            systemName:
                                "location.fill"
                        )
                    }
                    .accessibilityLabel(
                        placeTR("Refresh location", "Oppdater posisjon")
                    )
                }
            }
            .onAppear {
                location.start()
            }
            .onDisappear {
                location.stop()
            }
            .task(
                id:
                    location
                        .location?
                        .timestamp
            ) {
                await loadPlaces()
            }
        }
    }

    private var privacyBanner:
        some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            Image(
                systemName:
                    "lock.shield.fill"
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    placeTR("Private check-in", "Privat innsjekking")
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    placeTR("This place is saved to your workout only. It is not added to your public activity automatically.", "Dette stedet lagres bare på økten din og deles ikke automatisk på aktiviteten din.")
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
        }
        .padding(12)
        .background(
            ATHLTHTheme
                .accentSoft
                .opacity(0.70),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func placeSection(
        title: String,
        icon: String,
        places source:
            [WorkoutPlacePresentation]
    ) -> some View {
        if !source.isEmpty {
            VStack(
                alignment: .leading,
                spacing: 9
            ) {
                Label(
                    title,
                    systemImage: icon
                )
                .font(
                    .headline.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                VStack(spacing: 8) {
                    ForEach(source) {
                        place in

                        placeRow(place)
                    }
                }
            }
        }
    }

    private func placeRow(
        _ place:
            WorkoutPlacePresentation
    ) -> some View {
        let venueSymbol =
            place.placeKind == "hotel"
                ? "building.2.fill"
                : place.placeKind == "stadium"
                    ? "sportscourt.fill"
                    : "dumbbell.fill"
        let venueType =
            place.placeKind == "hotel"
                ? placeTR("Hotel", "Hotell")
                : place.placeKind == "stadium"
                    ? placeTR("Stadium", "Idrettsanlegg")
                    : placeTR("Gym", "Treningssenter")

        let distance =
            place.distanceMeters
        let canCheckIn =
            distance.map {
                $0.isFinite &&
                $0 >= 0 &&
                $0 <= 150
            } ?? false

        return Button {
            guard canCheckIn else {
                return
            }

            savingPlaceID =
                place.id
            errorMessage = nil

            Task {
                let success =
                    await places.checkIn(
                        workoutID:
                            workoutID,
                        userID:
                            session.profile
                                .userID,
                        place: place
                    )

                savingPlaceID = nil

                if success {
                    dismiss()
                } else {
                    errorMessage =
                        places.errorMessage
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: venueSymbol)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    canCheckIn
                        ? ATHLTHTheme
                            .vitality
                        : ATHLTHTheme
                            .mutedText
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    canCheckIn
                        ? ATHLTHTheme
                            .vitalitySoft
                        : Color.primary
                            .opacity(0.04),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(place.name)
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
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(venueType)
                        if let distance {
                            Text("·")
                            Text(distanceText(distance))
                        }

                        let count =
                            places.visitCount(
                                placeID:
                                    place.id
                            )

                        if count > 0 {
                            Text("·")
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "\(count) previous",
                                    norwegian: "\(count) tidligere"
                                )
                            )
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                if savingPlaceID ==
                    place.id {
                    ProgressView()
                        .controlSize(
                            .small
                        )
                } else if canCheckIn {
                    Image(
                        systemName:
                            "checkmark.circle"
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accent
                    )
                } else {
                    Text(placeTR("Too far", "For langt unna"))
                        .font(
                            .caption2.weight(
                                .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                }
            }
            .padding(12)
            .background(
                Color.white.opacity(
                    0.94
                ),
                in: RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.border,
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(
            !canCheckIn ||
            savingPlaceID != nil
        )
    }

    @MainActor
    private func loadPlaces()
        async {
        guard let currentLocation =
                location.location
        else {
            return
        }

        // A new GPS fix can arrive while MapKit is still responding.
        // Ignore ordinary drift instead of restarting the venue search.
        let explicitlyRequested = forceNextSearch
        forceNextSearch = false
        if !explicitlyRequested,
           let lastSearchLocation,
           let lastSearchAt,
           Date().timeIntervalSince(lastSearchAt) < 60,
           currentLocation.distance(from: lastSearchLocation) < 30 {
            return
        }

        lastSearchLocation = currentLocation
        lastSearchAt = Date()
        loading = true
        errorMessage = nil

        defer {
            loading = false
        }

        do {
            nearby =
                try await places
                    .nearbyFitnessCenters(
                        near:
                            currentLocation
                    )

            // Show nearby gyms as soon as MapKit answers. Resolving
            // older Apple Place IDs can be slower and is supplementary.
            loading = false
            frequent =
                await places
                    .resolvedFrequentPlaces(
                        near:
                            currentLocation
                    )
                    .filter {
                        item in

                        !nearby.contains {
                            $0.id ==
                                item.id
                        }
                    }
        } catch is CancellationError {
            // A replaced GPS task must not block the next valid search.
            lastSearchAt = nil
            return
        } catch let mapError as MKError
            where mapError.code == .placemarkNotFound {
            nearby = []
            frequent =
                await places
                    .resolvedFrequentPlaces(
                        near:
                            currentLocation
                    )
            errorMessage = nil
        } catch {
            lastSearchAt = nil
            errorMessage =
                error.localizedDescription
        }
    }

    private func distanceText(
        _ meters: Double
    ) -> String {
        let rounded = Int(max(meters, 0).rounded())
        return ATHLTHLocalization.choose(
            english: "\(rounded) m away",
            norwegian: "\(rounded) m unna"
        )
    }
}

@MainActor
private final class
    WorkoutPlaceLocationStore:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate,
    @unchecked Sendable {
    @Published private(set)
    var location: CLLocation?

    @Published private(set)
    var isUpdating = false

    @Published private(set)
    var authorizationStatus:
        CLAuthorizationStatus

    private let manager =
        CLLocationManager()

    override init() {
        authorizationStatus =
            manager.authorizationStatus

        super.init()

        manager.delegate = self
        manager.desiredAccuracy =
            kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
        manager.pausesLocationUpdatesAutomatically =
            true
    }

    func start() {
        authorizationStatus =
            manager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            manager
                .requestWhenInUseAuthorization()

        case .authorizedWhenInUse,
             .authorizedAlways:
            refresh()

        default:
            isUpdating = false
        }
    }

    func refresh() {
        guard authorizationStatus ==
                .authorizedWhenInUse ||
              authorizationStatus ==
                .authorizedAlways
        else {
            start()
            return
        }

        isUpdating = true
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    nonisolated func
        locationManagerDidChangeAuthorization(
            _ manager: CLLocationManager
        ) {
        let status =
            manager.authorizationStatus

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.authorizationStatus =
                status

            if status ==
                .authorizedWhenInUse ||
                status ==
                .authorizedAlways {
                self.refresh()
            } else {
                self.isUpdating = false
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations:
            [CLLocation]
    ) {
        guard let newest =
                locations.last
        else {
            return
        }

        Task { @MainActor [weak self] in
            self?.location = newest
            self?.isUpdating = false
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isUpdating = false
        }
    }
}
