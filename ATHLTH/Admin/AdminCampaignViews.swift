import SwiftUI

struct AdminGeneralCampaignComposerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ObservedObject var store: AdminControlCenterStore

    @State private var title = ""
    @State private var message = ""
    @State private var channels: Set<CampaignChannel> = [.inApp]
    @State private var showingConfirmation = false
    @State private var savedPreview = false

    var body: some View {
        Form {
            Section("Audience") {
                LabeledContent("Audience", value: CampaignAudience.freeUsers.title)
                LabeledContent(
                    "Free users · preview",
                    value: store.previewGeneralFreeAudience().formatted(.number)
                )

                Text("In production, delivery must still filter by channel eligibility and applicable marketing consent. Selecting Free users never overrides an individual user's communication choices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Campaign") {
                TextField("Campaign title", text: $title)

                TextField(
                    "Message",
                    text: $message,
                    axis: .vertical
                )
                .lineLimit(4...8)
            }

            Section("Channels") {
                ForEach(CampaignChannel.allCases) { channel in
                    Toggle(
                        isOn: Binding(
                            get: { channels.contains(channel) },
                            set: { enabled in
                                if enabled {
                                    channels.insert(channel)
                                } else {
                                    channels.remove(channel)
                                }
                            }
                        )
                    ) {
                        Label(channel.title, systemImage: channel.systemImage)
                    }
                }
            }

            Section("Delivery gate") {
                Label("Campaign delivery is disabled in V0.1.", systemImage: "lock.shield.fill")
                    .foregroundStyle(.green)

                Text("The composer, audience preview and history are ready. A backend delivery service must be connected and explicitly enabled before ATHLTH can send a real campaign.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Prepare Free-user campaign") {
                    showingConfirmation = true
                }
                .disabled(!canPrepare)

                Button("Send to Free users") {}
                    .disabled(true)

                if savedPreview {
                    Label(
                        "Campaign was added to history as blocked / not sent.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Free-user Campaign")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Prepare campaign?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Add to campaign history") {
                store.saveBlockedFreeCampaignDraft(
                    title: title,
                    message: message,
                    channels: channels,
                    actorUsername: session.profile.username
                )
                savedPreview = true
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This records the campaign configuration but does not send anything.")
        }
    }

    private var canPrepare: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !channels.isEmpty
    }
}

struct AdminCampaignHistoryView: View {
    @ObservedObject var store: AdminControlCenterStore
    @State private var statusFilter: CampaignDeliveryStatus?

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $statusFilter) {
                    Text("All").tag(CampaignDeliveryStatus?.none)
                    Text("Sent").tag(CampaignDeliveryStatus?.some(.sent))
                    Text("Blocked").tag(CampaignDeliveryStatus?.some(.blocked))
                    Text("Draft").tag(CampaignDeliveryStatus?.some(.draft))
                }
                .pickerStyle(.segmented)
            }

            Section("Campaigns") {
                ForEach(filteredHistory) { campaign in
                    NavigationLink {
                        AdminCampaignHistoryDetailView(campaign: campaign)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(campaign.title)
                                    .font(.headline)

                                Spacer()

                                Text(campaign.status.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor(campaign.status))
                            }

                            Text(campaign.audience.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text(campaign.createdAt.formatted(date: .abbreviated, time: .omitted))
                                Text("·")
                                Text(campaign.channels.map(\.title).sorted().joined(separator: ", "))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("History is demo/local data in V0.1. Production campaign records should be immutable server-side audit records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Campaign History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredHistory: [CampaignHistoryRecord] {
        store.campaignHistory
            .filter { statusFilter == nil || $0.status == statusFilter }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func statusColor(_ status: CampaignDeliveryStatus) -> Color {
        switch status {
        case .sent:
            return .green
        case .blocked, .cancelled:
            return .orange
        case .draft, .scheduled:
            return .secondary
        }
    }
}

private struct AdminCampaignHistoryDetailView: View {
    let campaign: CampaignHistoryRecord

    var body: some View {
        List {
            Section("Campaign") {
                LabeledContent("Title", value: campaign.title)
                LabeledContent("Audience", value: campaign.audience.title)
                LabeledContent("Status", value: campaign.status.title)
                LabeledContent(
                    "Channels",
                    value: campaign.channels.map(\.title).sorted().joined(separator: ", ")
                )
                LabeledContent("Created by", value: "@\(campaign.createdByUsername)")
                LabeledContent(
                    "Created",
                    value: campaign.createdAt.formatted(date: .abbreviated, time: .shortened)
                )

                if let sentAt = campaign.sentAt {
                    LabeledContent(
                        "Sent",
                        value: sentAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            Section("Message") {
                Text(campaign.message)
            }

            Section("Performance") {
                metric("Audience", campaign.audienceCount)
                metric("Delivered", campaign.deliveredCount)
                metric("Opened", campaign.openedCount)
                metric("Converted", campaign.convertedCount)
            }

            Section("Recorded recipients") {
                if campaign.recipients.isEmpty {
                    Text("No recipient records are stored for this preview campaign.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(campaign.recipients) { recipient in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("@\(recipient.username)")
                                .font(.headline)

                            if let deliveredAt = recipient.deliveredAt {
                                Text("Delivered \(deliveredAt.formatted(date: .abbreviated, time: .shortened))")
                            }

                            if let openedAt = recipient.openedAt {
                                Text("Opened \(openedAt.formatted(date: .abbreviated, time: .shortened))")
                            }

                            if let convertedAt = recipient.convertedAt {
                                Text("Converted \(convertedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Campaign")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func metric(_ title: String, _ value: Int) -> some View {
        LabeledContent(title, value: value.formatted(.number))
    }
}

struct AdminUserCampaignEventView: View {
    let event: UserCampaignEvent

    var body: some View {
        List {
            Section("Campaign") {
                LabeledContent("Campaign", value: event.campaignTitle)
                LabeledContent("Status", value: event.status.title)
                LabeledContent(
                    "Channels",
                    value: event.channels.map(\.title).sorted().joined(separator: ", ")
                )
            }

            Section("User timeline") {
                if let sentAt = event.sentAt {
                    timelineRow(
                        title: "Delivered",
                        date: sentAt,
                        systemImage: "paperplane.fill"
                    )
                }

                if let openedAt = event.openedAt {
                    timelineRow(
                        title: "Opened",
                        date: openedAt,
                        systemImage: "envelope.open.fill"
                    )
                }

                if let convertedAt = event.convertedAt {
                    timelineRow(
                        title: "Converted",
                        date: convertedAt,
                        systemImage: "checkmark.seal.fill"
                    )
                }

                if event.sentAt == nil {
                    Label(
                        "This campaign was not delivered to the user.",
                        systemImage: "nosign"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Campaign Event")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func timelineRow(
        title: String,
        date: Date,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
