import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let monthlyProductID = "com.wesc9.athlth.paid.monthly"
    static let yearlyProductID = "com.wesc9.athlth.paid.yearly"

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInProgress = false
    @Published var errorMessage: String?

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await Product.products(
                for: [
                    Self.monthlyProductID,
                    Self.yearlyProductID
                ]
            )

            products = loaded.sorted { lhs, rhs in
                planOrder(lhs.id) < planOrder(rhs.id)
            }
        } catch {
            products = []
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = true
        errorMessage = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                return true

            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    private func planOrder(_ id: String) -> Int {
        switch id {
        case Self.monthlyProductID: return 0
        case Self.yearlyProductID: return 1
        default: return 2
        }
    }

    private func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw SubscriptionStoreError.failedVerification
        }
    }
}

enum SubscriptionStoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified."
    }
}
