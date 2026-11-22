import Foundation
import Supabase

private struct ATHLTHDuelReplyDeadlineParams: Encodable {
    let p_challenge: UUID
    let p_days: Int
}

struct ATHLTHDuelReplyDeadlineCloud {
    func update(_ challengeID: UUID, days: Int) async throws {
        guard (1...30).contains(days) else { return }
        try await SupabaseEnvironment.client.rpc(
            "athlth_duel_set_reply_days",
            params: ATHLTHDuelReplyDeadlineParams(
                p_challenge: challengeID, p_days: days
            )
        ).execute()
    }
}
