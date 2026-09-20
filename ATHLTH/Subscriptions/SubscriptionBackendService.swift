import Foundation
import Supabase

@MainActor
final class SubscriptionBackendService: ObservableObject {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func submit(_ proof: AppStoreTransactionProof) async throws {
        guard client.auth.currentUser != nil else {
            throw SupabaseAccountError.notAuthenticated
        }

        try await client
            .rpc(
                "submit_app_store_transaction",
                params: AppStoreTransactionSubmissionParams(
                    transactionID: proof.transactionID,
                    originalTransactionID: proof.originalTransactionID,
                    productID: proof.productID,
                    appAccountToken: proof.appAccountToken,
                    signedTransactionInfo: proof.signedTransactionInfo
                )
            )
            .execute()
    }
}

private struct AppStoreTransactionSubmissionParams: Encodable {
    let transactionID: String
    let originalTransactionID: String
    let productID: String
    let appAccountToken: UUID?
    let signedTransactionInfo: String

    enum CodingKeys: String, CodingKey {
        case transactionID = "p_transaction_id"
        case originalTransactionID = "p_original_transaction_id"
        case productID = "p_product_id"
        case appAccountToken = "p_app_account_token"
        case signedTransactionInfo = "p_signed_transaction_info"
    }
}
