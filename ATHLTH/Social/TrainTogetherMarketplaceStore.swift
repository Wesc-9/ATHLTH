import Foundation
import Supabase

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

    private let client =
        SupabaseEnvironment.client

    func refresh() async {
        guard !isLoading else {
            return
        }

        isLoading = true
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

            let (
                loadedPosts,
                loadedRequests
            ) = try await (
                postsQuery,
                requestsQuery
            )

            posts = loadedPosts
            requests = loadedRequests
            errorMessage = nil
        } catch {
            errorMessage =
                error.localizedDescription
        }
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
            errorMessage =
                error.localizedDescription
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
            errorMessage =
                error.localizedDescription
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
            errorMessage =
                error.localizedDescription
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
            errorMessage =
                error.localizedDescription
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
            errorMessage =
                error.localizedDescription
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
