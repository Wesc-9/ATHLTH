import SwiftUI

struct CommunityGroupEventEditView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var advanced =
        CommunityGroupAdvancedStore()

    let group: CommunityGroupRecord
    let event: CommunityGroupEventRecord
    let existingHostIDs: Set<UUID>
    let onSaved: () -> Void

    @State private var title: String
    @State private var summary: String
    @State private var startsAt: Date
    @State private var meetingName: String
    @State private var activityDraft:
        CommunityGroupActivityDraft
    @State private var options:
        CommunityGroupEventAdvancedOptions
    @State private var cohostIDs: Set<UUID>
    @State private var saving = false
    @State private var saveError: String?

    init(
        group: CommunityGroupRecord,
        event: CommunityGroupEventRecord,
        existingHostIDs: Set<UUID>,
        onSaved: @escaping () -> Void
    ) {
        self.group = group
        self.event = event
        self.existingHostIDs = existingHostIDs
        self.onSaved = onSaved

        _title = State(initialValue: event.title)
        _summary = State(initialValue: event.summary)
        _startsAt = State(initialValue: event.startsAt)
        _meetingName = State(
            initialValue: event.meetingName
        )
        _activityDraft = State(
            initialValue:
                CommunityGroupActivityDraft.existing(
                    event.activityConfiguration
                )
        )

        var initialOptions =
            CommunityGroupEventAdvancedOptions()
        initialOptions.organizerKind =
            event.organizerKind
        initialOptions.status =
            CommunityGroupContentStatus(
                rawValue: event.status
            ) ?? .upcoming
        initialOptions.capacity =
            event.capacity
        initialOptions.rsvpDeadline =
            event.rsvpDeadline
        initialOptions.endsAt =
            event.endsAt
        initialOptions.meetingLatitude =
            event.meetingLatitude
        initialOptions.meetingLongitude =
            event.meetingLongitude
        initialOptions.repeatWeekly =
            event.repeatRule == "weekly"
        initialOptions.repeatUntil =
            event.repeatUntil

        _options = State(
            initialValue: initialOptions
        )
        _cohostIDs = State(
            initialValue: existingHostIDs
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField(
                        "Title",
                        text: $title
                    )

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    DatePicker(
                        "Starts",
                        selection: $startsAt,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                }

                CommunityGroupActivityEditor(
                    draft: $activityDraft
                )

                Section("Meet") {
                    TextField(
                        "Meeting point (optional)",
                        text: $meetingName
                    )
                }

                CommunityGroupEventAdvancedEditor(
                    group: group,
                    eventStartsAt: startsAt,
                    options: $options,
                    cohostIDs: $cohostIDs,
                    routeStart:
                        activityDraft
                            .configuration
                            .route?
                            .coordinates
                            .first
                )

                Section {
                    Label(
                        "Important changes such as time, meeting point or activity notify people who are going, maybe going or waitlisted.",
                        systemImage: "bell.badge"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? "Saving…"
                            : "Save"
                    ) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(
                "Could Not Save Event",
                isPresented: Binding(
                    get: {
                        saveError != nil ||
                        advanced.errorMessage != nil
                    },
                    set: {
                        if !$0 {
                            saveError = nil
                            advanced.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    saveError ??
                    advanced.errorMessage ??
                    ""
                )
            }
        }
    }

    private var canSave: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        activityDraft.validationMessage == nil &&
        !saving
    }

    private func save() {
        if let validation =
            activityDraft.validationMessage {
            saveError = validation
            return
        }

        if let deadline = options.rsvpDeadline,
           deadline > startsAt {
            saveError =
                "RSVP deadline must be before the event starts."
            return
        }

        if let endsAt = options.endsAt,
           endsAt <= startsAt {
            saveError =
                "Event end must be after the start."
            return
        }

        Task {
            saving = true

            let updated =
                await advanced.updateEvent(
                    eventID: event.id,
                    title: title,
                    summary: summary,
                    activityType:
                        activityDraft
                            .configuration
                            .activityType,
                    startsAt: startsAt,
                    meetingName: meetingName,
                    activityConfiguration:
                        activityDraft
                            .configuration,
                    options: options
                )

            if updated {
                let hostsSaved =
                    await advanced.setHosts(
                        groupID: group.id,
                        contentType: "event",
                        contentID: event.id,
                        userIDs:
                            Array(cohostIDs)
                    )

                if hostsSaved {
                    saving = false
                    onSaved()
                    dismiss()
                    return
                }
            }

            saving = false
        }
    }
}

struct CommunityGroupChallengeEditView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var advanced =
        CommunityGroupAdvancedStore()

    let group: CommunityGroupRecord
    let challenge: CommunityGroupChallengeRecord
    let existingHostIDs: Set<UUID>
    let onSaved: () -> Void

    @State private var title: String
    @State private var summary: String
    @State private var metric:
        CommunityGroupChallengeMetric
    @State private var target: String
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var activityDraft:
        CommunityGroupActivityDraft
    @State private var options:
        CommunityGroupChallengeAdvancedOptions
    @State private var cohostIDs: Set<UUID>
    @State private var saving = false
    @State private var saveError: String?

    init(
        group: CommunityGroupRecord,
        challenge: CommunityGroupChallengeRecord,
        existingHostIDs: Set<UUID>,
        onSaved: @escaping () -> Void
    ) {
        self.group = group
        self.challenge = challenge
        self.existingHostIDs = existingHostIDs
        self.onSaved = onSaved

        _title = State(initialValue: challenge.title)
        _summary = State(initialValue: challenge.summary)
        _metric = State(initialValue: challenge.metric)
        _target = State(
            initialValue: String(
                format: "%.2f",
                challenge.targetValue
            )
        )
        _startsAt = State(
            initialValue: challenge.startsAt
        )
        _endsAt = State(
            initialValue: challenge.endsAt
        )
        _activityDraft = State(
            initialValue:
                CommunityGroupActivityDraft.existing(
                    challenge
                        .activityConfiguration
                )
        )

        var initialOptions =
            CommunityGroupChallengeAdvancedOptions()
        initialOptions.organizerKind =
            challenge.organizerKind
        initialOptions.status =
            CommunityGroupContentStatus(
                rawValue: challenge.status
            ) ?? .upcoming
        initialOptions.scoringMode =
            challenge.scoringMode
        initialOptions.attemptLimit =
            challenge.attemptLimit
        initialOptions.routeVerificationEnabled =
            challenge.routeVerificationEnabled
        initialOptions.routeToleranceMeters =
            challenge.routeToleranceMeters
        initialOptions.joinRequired =
            challenge.joinRequired

        _options = State(
            initialValue: initialOptions
        )
        _cohostIDs = State(
            initialValue: existingHostIDs
        )
    }

    private var rulesLocked: Bool {
        Date() >= challenge.startsAt
    }

    private var targetValue: Double? {
        Double(
            target
                .replacingOccurrences(
                    of: ",",
                    with: "."
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge") {
                    TextField(
                        "Title",
                        text: $title
                    )

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Group {
                    CommunityGroupActivityEditor(
                        draft: $activityDraft
                    )

                    Section("Goal") {
                        Picker(
                            "Metric",
                            selection: $metric
                        ) {
                            ForEach(
                                CommunityGroupChallengeMetric
                                    .allCases
                            ) {
                                Label(
                                    $0.title,
                                    systemImage:
                                        $0.icon
                                )
                                .tag($0)
                            }
                        }

                        HStack {
                            TextField(
                                "Target",
                                text: $target
                            )
                            .keyboardType(
                                .decimalPad
                            )

                            Text(metric.unit)
                                .foregroundStyle(
                                    .secondary
                                )
                        }

                        Picker(
                            "Scoring",
                            selection:
                                $options.scoringMode
                        ) {
                            ForEach(
                                CommunityGroupScoringMode
                                    .allCases
                            ) {
                                Text($0.title)
                                    .tag($0)
                            }
                        }
                    }

                    Section("Window") {
                        DatePicker(
                            "Starts",
                            selection: $startsAt,
                            displayedComponents: [
                                .date,
                                .hourAndMinute
                            ]
                        )

                        DatePicker(
                            "Ends",
                            selection: $endsAt,
                            in: startsAt...,
                            displayedComponents: [
                                .date,
                                .hourAndMinute
                            ]
                        )
                    }
                }
                .disabled(rulesLocked)

                CommunityGroupChallengeAdvancedEditor(
                    group: group,
                    rulesLocked: rulesLocked,
                    options: $options,
                    cohostIDs: $cohostIDs,
                    routeSelected:
                        activityDraft.mode ==
                            .route &&
                        (
                            activityDraft
                                .selectedRoute != nil ||
                            activityDraft
                                .selectedRouteSnapshot != nil
                        )
                )

                if rulesLocked {
                    Section {
                        Label(
                            "Activity, target, time window, attempts and verification are locked because this challenge has started. Name, description, organizer, co-hosts and status can still be managed.",
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? "Saving…"
                            : "Save"
                    ) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(
                "Could Not Save Challenge",
                isPresented: Binding(
                    get: {
                        saveError != nil ||
                        advanced.errorMessage != nil
                    },
                    set: {
                        if !$0 {
                            saveError = nil
                            advanced.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    saveError ??
                    advanced.errorMessage ??
                    ""
                )
            }
        }
    }

    private var canSave: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        (targetValue ?? 0) > 0 &&
        endsAt > startsAt &&
        activityDraft.validationMessage == nil &&
        !saving
    }

    private func save() {
        guard let targetValue,
              targetValue > 0
        else {
            saveError =
                "Choose a valid target."
            return
        }

        if !rulesLocked,
           let validation =
            activityDraft.validationMessage {
            saveError = validation
            return
        }

        Task {
            saving = true

            let updated =
                await advanced.updateChallenge(
                    challengeID:
                        challenge.id,
                    title: title,
                    summary: summary,
                    metric: metric,
                    targetValue:
                        targetValue,
                    startsAt: startsAt,
                    endsAt: endsAt,
                    activityConfiguration:
                        activityDraft
                            .configuration,
                    options: options
                )

            if updated {
                let hostsSaved =
                    await advanced.setHosts(
                        groupID: group.id,
                        contentType:
                            "challenge",
                        contentID:
                            challenge.id,
                        userIDs:
                            Array(cohostIDs)
                    )

                if hostsSaved {
                    saving = false
                    onSaved()
                    dismiss()
                    return
                }
            }

            saving = false
        }
    }
}
