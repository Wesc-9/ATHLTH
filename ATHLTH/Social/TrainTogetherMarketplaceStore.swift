import Foundation
import Supabase

/// A cancelled task is not an application error. SwiftUI can cancel
/// view-scoped refresh tasks when their view is dismissed or replaced.
enum TrainTogetherMarketplaceErrorPolicy {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain &&
            nsError.code == NSURLErrorCancelled
    }
}

@MainActor
final class TrainTogetherMarketplaceStore:
    ObservableObject
{
    @Published private(set) var posts:
        [TrainTogetherPost] = []
    @Published private(set) var requests:
        [TrainTogetherRequest] = []
    @Published private(set) var meetups:
        [UUID: TrainTogetherMeetup] = [:]
    @Published private(set) var isLoading =
        false
    @Published private(set) var isWorking =
        false
    @Published var errorMessage: String?
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var hasLoaded = false

    private let client =
        SupabaseEnvironment.client
    private var lastSuccessfulRefresh: Date?

    /// A lightweight caller can share the existing Marketplace refresh logic
    /// without repeatedly fetching public posts on every Community appearance.
    func refreshIfStale(maxAge: TimeInterval = 120) async {
        if let lastSuccessfulRefresh,
           Date().timeIntervalSince(lastSuccessfulRefresh) < maxAge {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        refreshErrorMessage = nil
        defer { isLoading = false }

        do {
            let lowerBound =
                Date()
                    .addingTimeInterval(
                        -2 * 60 * 60
                    )

            async let postsQuery:
                [TrainTogetherPost] =
                client
                    .from(
                        "train_together_posts"
                    )
                    .select()
                    .gte(
                        "scheduled_start",
                        value:
                            lowerBound
                                .ISO8601Format()
                    )
                    .order(
                        "scheduled_start",
                        ascending: true
                    )
                    .limit(200)
                    .execute()
                    .value

            // Past entries are only returned when the logged-in athlete
            // hosted or joined: server-side RLS prevents reading strangers'
            // old sessions. Retain a small 14-day window for shared recaps.
            async let archiveQuery: [TrainTogetherPost] = client
                .from("train_together_posts")
                .select()
                .gte(
                    "scheduled_start",
                    value: Date().addingTimeInterval(-14 * 86400).ISO8601Format()
                )
                .lt("scheduled_start", value: Date().ISO8601Format())
                .order("scheduled_start", ascending: false)
                .limit(50)
                .execute()
                .value

            async let requestsQuery:
                [TrainTogetherRequest] =
                client
                    .from(
                        "train_together_requests"
                    )
                    .select()
                    .order(
                        "created_at",
                        ascending: false
                    )
                    .limit(300)
                    .execute()
                    .value

            let (loadedPosts, loadedRequests, archives) = try await (
                postsQuery,
                requestsQuery,
                archiveQuery
            )

            var unique: [UUID: TrainTogetherPost] = [:]
            for post in archives + loadedPosts {
                unique[post.id] = post
            }
            posts = unique.values.sorted {
                $0.scheduledStart < $1.scheduledStart
            }
            requests = loadedRequests
            lastSuccessfulRefresh = Date()
            hasLoaded = true
            refreshErrorMessage = nil
        } catch {
            // Navigation and pull-to-refresh can cancel the in-flight
            // Supabase queries. Never show a system CancellationError alert.
            guard !Task.isCancelled,
                  !TrainTogetherMarketplaceErrorPolicy.isCancellation(error)
            else {
                return
            }

            // Keep any previously loaded posts while offering a retry.
            // Do not turn a genuine network/database failure into
            // a misleading "No workouts" empty state.
            refreshErrorMessage = error.localizedDescription
        }
    }

    private func recordActionError(_ error: Error) {
        guard !Task.isCancelled,
              !TrainTogetherMarketplaceErrorPolicy.isCancellation(error)
        else {
            return
        }
        errorMessage = error.localizedDescription
    }

    func publish(
        post: TrainTogetherPostWrite,
        meetup: TrainTogetherMeetupWrite?
    ) async -> Bool {
        guard !isWorking else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await client
                .from(
                    "train_together_posts"
                )
                .insert(post)
                .execute()

            if let meetup,
               meetup.meetingName != nil ||
                meetup.meetingDetails != nil {
                try await client
                    .from(
                        "train_together_post_meetups"
                    )
                    .insert(meetup)
                    .execute()
            }

            await refresh()
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func requestToJoin(
        postID: UUID,
        message: String?
    ) async -> Bool {
        guard !isWorking else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await client
                .rpc(
                    "request_train_together_join",
                    params:
                        RequestJoinParams(
                            postID: postID,
                            message: message
                        )
                )
                .execute()

            await refresh()
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func joinOpen(
        postID: UUID
    ) async -> Bool {
        guard !isWorking else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await client
                .rpc(
                    "join_train_together_open",
                    params:
                        OpenJoinParams(
                            postID: postID
                        )
                )
                .execute()

            await refresh()
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func withdraw(
        requestID: UUID
    ) async -> Bool {
        guard !isWorking else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await client
                .rpc(
                    "withdraw_train_together_request",
                    params:
                        RequestIDParams(
                            requestID:
                                requestID
                        )
                )
                .execute()

            await refresh()
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func respond(
        requestID: UUID,
        accept: Bool
    ) async -> Bool {
        guard !isWorking else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await client
                .rpc(
                    "respond_train_together_request",
                    params:
                        RespondParams(
                            requestID:
                                requestID,
                            action:
                                accept
                                    ? "accept"
                                    : "decline"
                        )
                )
                .execute()

            await refresh()
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func cancel(
        postID: UUID
    ) async -> Bool {
        guard !isWorking else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await client
                .rpc(
                    "cancel_train_together_post",
                    params:
                        CancelPostParams(
                            postID: postID
                        )
                )
                .execute()

            await refresh()
            return true
        } catch {
            recordActionError(error)
            return false
        }
    }

    func loadMeetup(
        postID: UUID
    ) async {
        do {
            let rows:
                [TrainTogetherMeetup] =
                try await client
                    .from(
                        "train_together_post_meetups"
                    )
                    .select()
                    .eq(
                        "post_id",
                        value: postID
                    )
                    .limit(1)
                    .execute()
                    .value

            if let meetup = rows.first {
                meetups[postID] =
                    meetup
            }
        } catch {
            // A non-accepted viewer is expected
            // to have no access to meetup data.
        }
    }

    func request(
        for postID: UUID,
        userID: UUID
    ) -> TrainTogetherRequest? {
        requests.first {
            $0.postID == postID &&
            $0.requesterID == userID
        }
    }

    func incomingRequests(
        for postID: UUID
    ) -> [TrainTogetherRequest] {
        requests
            .filter {
                $0.postID == postID
            }
            .sorted {
                $0.createdAt >
                    $1.createdAt
            }
    }

    func acceptedRequest(
        postID: UUID,
        userID: UUID
    ) -> TrainTogetherRequest? {
        requests.first {
            $0.postID == postID &&
            $0.requesterID == userID &&
            $0.state == .accepted
        }
    }
}

private struct RequestJoinParams:
    Encodable
{
    let postID: UUID
    let message: String?

    enum CodingKeys:
        String,
        CodingKey
    {
        case postID = "p_post_id"
        case message = "p_message"
    }
}

private struct OpenJoinParams:
    Encodable
{
    let postID: UUID

    enum CodingKeys:
        String,
        CodingKey
    {
        case postID = "p_post_id"
    }
}

private struct RequestIDParams:
    Encodable
{
    let requestID: UUID

    enum CodingKeys:
        String,
        CodingKey
    {
        case requestID =
            "p_request_id"
    }
}

private struct RespondParams:
    Encodable
{
    let requestID: UUID
    let action: String

    enum CodingKeys:
        String,
        CodingKey
    {
        case requestID =
            "p_request_id"
        case action = "p_action"
    }
}

private struct CancelPostParams:
    Encodable
{
    let postID: UUID

    enum CodingKeys:
        String,
        CodingKey
    {
        case postID = "p_post_id"
    }
}
