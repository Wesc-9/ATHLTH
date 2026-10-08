@preconcurrency import CoreLocation
import MapKit
import SwiftUI

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

                    Text("Private")
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
            return "Trained at \(place.name)"
        }

        return "Training place"
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
                    Text("Training place")
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
                            ? "Add the fitness center for this workout."
                            : "Saved privately to this workout."
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
                                        ? "Loading place…"
                                        : "Training place"
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
                        Text("Change")
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button(
                            "Remove place",
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
                        "Add training place",
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
                "ATHLTH stores the Apple Place ID, not a separate copy of the venue address. Place check-ins are private unless you explicitly choose to share them later."
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
        .padding(16)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
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
            return "First workout here"
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
                                "Finding fitness centers within 150 m…"
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
                                "Places you train often",
                            icon:
                                "star.fill",
                            places:
                                frequent
                        )
                    }

                    placeSection(
                        title: "Nearby",
                        icon:
                            "location.fill",
                        places:
                            nearby
                    )

                    if !loading,
                       !location.isUpdating,
                       nearby.isEmpty {
                        ContentUnavailableView(
                            "No fitness center within 150 m",
                            systemImage:
                                "figure.strengthtraining.traditional",
                            description:
                                Text(
                                    "Move closer to the venue and refresh. ATHLTH only allows a check-in when you're physically nearby."
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
                "Training place"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button {
                        location.refresh()
                    } label: {
                        Image(
                            systemName:
                                "location.fill"
                        )
                    }
                    .accessibilityLabel(
                        "Refresh location"
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
                    "Private check-in"
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
                    "This place is saved to your workout only. It is not added to your public activity automatically."
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
                Image(
                    systemName:
                        "figure.strengthtraining.traditional"
                )
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
                        if let distance {
                            Text(
                                distanceText(
                                    distance
                                )
                            )
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
                    Text("Too far")
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
