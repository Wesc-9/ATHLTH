import MapKit
import SwiftUI

struct CommunityGroupEventAdvancedEditor: View {
    @EnvironmentObject private var groups:
        CommunityGroupStore
    @EnvironmentObject private var session:
        AppSessionStore

    let group: CommunityGroupRecord
    let eventStartsAt: Date
    @Binding var options:
        CommunityGroupEventAdvancedOptions
    @Binding var cohostIDs: Set<UUID>
    let routeStart: RouteCoordinate?

    var body: some View {
        Section("Organizer") {
            Picker(
                "Organizer",
                selection: $options.organizerKind
            ) {
                Label(
                    "Me",
                    systemImage: "person.fill"
                )
                .tag(
                    CommunityGroupOrganizerKind.person
                )

                Label(
                    group.name,
                    systemImage: "person.3.fill"
                )
                .tag(
                    CommunityGroupOrganizerKind.group
                )
            }

            NavigationLink {
                CommunityGroupCohostPickerView(
                    group: group,
                    selectedIDs: $cohostIDs
                )
            } label: {
                HStack {
                    Label(
                        "Co-hosts",
                        systemImage: "person.2.fill"
                    )

                    Spacer()

                    Text(
                        cohostIDs.isEmpty
                            ? "None"
                            : "\(cohostIDs.count)"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }

        Section("Participation") {
            Toggle(
                "Limit capacity",
                isOn: capacityEnabled
            )

            if options.capacity != nil {
                Stepper(
                    "Capacity: \(options.capacity ?? 20)",
                    value: capacityValue,
                    in: 1...5_000
                )
            }

            Toggle(
                "RSVP deadline",
                isOn: rsvpDeadlineEnabled
            )

            if let deadline =
                options.rsvpDeadline {
                DatePicker(
                    "Deadline",
                    selection:
                        Binding(
                            get: { deadline },
                            set: {
                                options.rsvpDeadline =
                                    $0
                            }
                        ),
                    displayedComponents: [
                        .date,
                        .hourAndMinute
                    ]
                )
            }

            Text(
                "When capacity is full, new Going responses are placed on a waitlist automatically."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Timing & place") {
            Toggle(
                "Set end time",
                isOn: endTimeEnabled
            )

            if let end = options.endsAt {
                DatePicker(
                    "Ends",
                    selection:
                        Binding(
                            get: { end },
                            set: {
                                options.endsAt = $0
                            }
                        ),
                    displayedComponents: [
                        .date,
                        .hourAndMinute
                    ]
                )
            }

            NavigationLink {
                CommunityGroupMeetingPointPicker(
                    latitude:
                        $options.meetingLatitude,
                    longitude:
                        $options.meetingLongitude,
                    routeStart: routeStart
                )
            } label: {
                HStack {
                    Label(
                        "Meeting point on map",
                        systemImage:
                            "mappin.and.ellipse"
                    )

                    Spacer()

                    Text(
                        options.meetingLatitude == nil
                            ? "Set"
                            : "Selected"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            if routeStart != nil {
                Button {
                    useRouteStart()
                } label: {
                    Label(
                        "Use route start",
                        systemImage:
                            "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
            }

            if options.meetingLatitude != nil {
                Button(
                    "Remove map point",
                    role: .destructive
                ) {
                    options.meetingLatitude = nil
                    options.meetingLongitude = nil
                }
            }
        }

        Section("Repeat & publishing") {
            Toggle(
                "Repeat weekly",
                isOn: repeatWeekly
            )

            if options.repeatWeekly {
                Toggle(
                    "Set repeat end date",
                    isOn: repeatEndEnabled
                )

                if let repeatUntil =
                    options.repeatUntil {
                    DatePicker(
                        "Repeat until",
                        selection:
                            Binding(
                                get: {
                                    repeatUntil
                                },
                                set: {
                                    options.repeatUntil =
                                        $0
                                }
                            ),
                        displayedComponents: .date
                    )
                }
            }

            Picker(
                "Status",
                selection: $options.status
            ) {
                Text("Publish")
                    .tag(
                        CommunityGroupContentStatus
                            .upcoming
                    )
                Text("Save as Draft")
                    .tag(
                        CommunityGroupContentStatus
                            .draft
                    )
            }
        }
    }

    private var capacityEnabled:
        Binding<Bool> {
        Binding(
            get: {
                options.capacity != nil
            },
            set: { enabled in
                options.capacity =
                    enabled
                        ? max(
                            options.capacity ?? 20,
                            1
                        )
                        : nil
            }
        )
    }

    private var capacityValue:
        Binding<Int> {
        Binding(
            get: {
                options.capacity ?? 20
            },
            set: {
                options.capacity = $0
            }
        )
    }

    private var rsvpDeadlineEnabled:
        Binding<Bool> {
        Binding(
            get: {
                options.rsvpDeadline != nil
            },
            set: { enabled in
                options.rsvpDeadline =
                    enabled
                        ? (
                            options.rsvpDeadline ??
                            min(
                                eventStartsAt.addingTimeInterval(
                                    -3_600
                                ),
                                Date().addingTimeInterval(
                                    3_600
                                )
                            )
                        )
                        : nil
            }
        )
    }

    private var endTimeEnabled:
        Binding<Bool> {
        Binding(
            get: {
                options.endsAt != nil
            },
            set: { enabled in
                options.endsAt =
                    enabled
                        ? (
                            options.endsAt ??
                            eventStartsAt.addingTimeInterval(
                                3_600
                            )
                        )
                        : nil
            }
        )
    }

    private var repeatWeekly:
        Binding<Bool> {
        Binding(
            get: {
                options.repeatWeekly
            },
            set: {
                options.repeatWeekly = $0

                if !$0 {
                    options.repeatUntil = nil
                }
            }
        )
    }

    private var repeatEndEnabled:
        Binding<Bool> {
        Binding(
            get: {
                options.repeatUntil != nil
            },
            set: { enabled in
                options.repeatUntil =
                    enabled
                        ? (
                            options.repeatUntil ??
                            Calendar.current.date(
                                byAdding: .month,
                                value: 3,
                                to: eventStartsAt
                            )
                        )
                        : nil
            }
        )
    }

    private func useRouteStart() {
        guard let routeStart else {
            return
        }

        options.meetingLatitude =
            routeStart.latitude
        options.meetingLongitude =
            routeStart.longitude
    }
}

struct CommunityGroupChallengeAdvancedEditor:
    View
{
    let group: CommunityGroupRecord
    var rulesLocked: Bool = false

    @Binding var options:
        CommunityGroupChallengeAdvancedOptions
    @Binding var cohostIDs: Set<UUID>

    let routeSelected: Bool

    var body: some View {
        Section("Organizer") {
            Picker(
                "Organizer",
                selection: $options.organizerKind
            ) {
                Label(
                    "Me",
                    systemImage: "person.fill"
                )
                .tag(
                    CommunityGroupOrganizerKind.person
                )

                Label(
                    group.name,
                    systemImage: "person.3.fill"
                )
                .tag(
                    CommunityGroupOrganizerKind.group
                )
            }

            NavigationLink {
                CommunityGroupCohostPickerView(
                    group: group,
                    selectedIDs: $cohostIDs
                )
            } label: {
                HStack {
                    Label(
                        "Co-hosts",
                        systemImage: "person.2.fill"
                    )

                    Spacer()

                    Text(
                        cohostIDs.isEmpty
                            ? "None"
                            : "\(cohostIDs.count)"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }

        Section("Participation & attempts") {
            Toggle(
                "Require Join Challenge",
                isOn: $options.joinRequired
            )

            Toggle(
                "Limit attempts",
                isOn: attemptLimitEnabled
            )

            if options.attemptLimit != nil {
                Stepper(
                    "Attempts: \(options.attemptLimit ?? 1)",
                    value: attemptLimitValue,
                    in: 1...100
                )
            }
        }
        .disabled(rulesLocked)

        Section("Verification") {
            Toggle(
                "Verify planned route",
                isOn:
                    $options.routeVerificationEnabled
            )
            .disabled(!routeSelected)

            if !routeSelected {
                Text(
                    "Choose a specific Route to enable GPS route verification."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if options.routeVerificationEnabled {
                Stepper(
                    "GPS tolerance: \(options.routeToleranceMeters) m",
                    value:
                        $options.routeToleranceMeters,
                    in: 25...500,
                    step: 25
                )

                Text(
                    "ATHLTH compares the completed Apple Health GPS track with the challenge route. At least 90% of the route must match within this tolerance."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if rulesLocked {
                Label(
                    "Competition rules are locked because the challenge has started.",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(rulesLocked)

        Section("Publishing") {
            Picker(
                "Status",
                selection: $options.status
            ) {
                Text("Publish")
                    .tag(
                        CommunityGroupContentStatus
                            .upcoming
                    )
                Text("Save as Draft")
                    .tag(
                        CommunityGroupContentStatus
                            .draft
                    )
            }
        }
    }

    private var attemptLimitEnabled:
        Binding<Bool> {
        Binding(
            get: {
                options.attemptLimit != nil
            },
            set: { enabled in
                options.attemptLimit =
                    enabled
                        ? max(
                            options.attemptLimit ?? 1,
                            1
                        )
                        : nil
            }
        )
    }

    private var attemptLimitValue:
        Binding<Int> {
        Binding(
            get: {
                options.attemptLimit ?? 1
            },
            set: {
                options.attemptLimit = $0
            }
        )
    }
}

struct CommunityGroupCohostPickerView: View {
    @EnvironmentObject private var groups:
        CommunityGroupStore
    @EnvironmentObject private var session:
        AppSessionStore

    let group: CommunityGroupRecord
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        List {
            ForEach(
                groups.members(in: group.id),
                id: \.userID
            ) { member in
                if member.userID !=
                    session.profile.userID {
                    Button {
                        toggle(member.userID)
                    } label: {
                        HStack(spacing: 12) {
                            if let profile =
                                groups.profileCard(
                                    for: member.userID
                                ) {
                                CommunityContentAvatar(
                                    profile: profile,
                                    size: 40
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        profile.resolvedName
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )

                                    if !profile
                                        .usernameLabel
                                        .isEmpty {
                                        Text(
                                            profile
                                                .usernameLabel
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                            } else {
                                Image(
                                    systemName:
                                        "person.crop.circle"
                                )
                                .font(.title2)

                                Text("Group member")
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )
                            }

                            Spacer()

                            Image(
                                systemName:
                                    selectedIDs
                                        .contains(
                                            member.userID
                                        )
                                        ? "checkmark.circle.fill"
                                        : "circle"
                            )
                            .foregroundStyle(
                                selectedIDs.contains(
                                    member.userID
                                )
                                    ? ATHLTHTheme
                                        .accentDeep
                                    : .secondary
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Co-hosts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

struct CommunityGroupMeetingPointPicker:
    View
{
    @Environment(\.dismiss) private var dismiss

    @Binding var latitude: Double?
    @Binding var longitude: Double?

    let routeStart: RouteCoordinate?

    @State private var position:
        MapCameraPosition = .automatic
    @State private var selectedCoordinate:
        CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $position) {
                    if let selectedCoordinate {
                        Marker(
                            "Meeting point",
                            coordinate:
                                selectedCoordinate
                        )
                    }

                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture {
                    point in

                    if let coordinate =
                        proxy.convert(
                            point,
                            from: .local
                        ) {
                        selectedCoordinate =
                            coordinate
                    }
                }
            }

            HStack(spacing: 10) {
                if let routeStart {
                    Button("Route Start") {
                        let coordinate =
                            CLLocationCoordinate2D(
                                latitude:
                                    routeStart.latitude,
                                longitude:
                                    routeStart.longitude
                            )
                        selectedCoordinate =
                            coordinate
                        position = .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span:
                                    MKCoordinateSpan(
                                        latitudeDelta:
                                            0.01,
                                        longitudeDelta:
                                            0.01
                                    )
                            )
                        )
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Use Point") {
                    guard let selectedCoordinate
                    else {
                        return
                    }

                    latitude =
                        selectedCoordinate.latitude
                    longitude =
                        selectedCoordinate.longitude
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    selectedCoordinate == nil
                )
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Meeting Point")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .cancellationAction
            ) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if let latitude,
               let longitude {
                let coordinate =
                    CLLocationCoordinate2D(
                        latitude: latitude,
                        longitude: longitude
                    )
                selectedCoordinate = coordinate
                position = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.01,
                            longitudeDelta: 0.01
                        )
                    )
                )
            } else if let routeStart {
                let coordinate =
                    CLLocationCoordinate2D(
                        latitude:
                            routeStart.latitude,
                        longitude:
                            routeStart.longitude
                    )
                selectedCoordinate = coordinate
                position = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.01,
                            longitudeDelta: 0.01
                        )
                    )
                )
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .automatic
                )
            }
        }
    }
}
