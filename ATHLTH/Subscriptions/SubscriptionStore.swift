import Foundation
import StoreKit

struct StoreSubscriptionEntitlement: Equatable, Sendable {
    let productID: String
    let transactionID: UInt64
    let originalTransactionID: UInt64
    let appAccountToken: UUID?
    let purchaseDate: Date
    let expirationDate: Date?
}

struct AppStoreTransactionProof: Equatable, Sendable {
    let transactionID: String
    let originalTransactionID: String
    let productID: String
    let appAccountToken: UUID?
    let signedTransactionInfo: String
}

@MainActor
final class SubscriptionStore: ObservableObject {
    static let monthlyProductID = "com.wesc9.athlth.plus.monthly"
    static let yearlyProductID = "com.wesc9.athlth.plus.yearly"

    static let productIDs: Set<String> = [
        monthlyProductID,
        yearlyProductID
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var activeEntitlement: StoreSubscriptionEntitlement?
    @Published private(set) var latestTransactionProof: AppStoreTransactionProof?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingEntitlements = false
    @Published private(set) var purchaseInProgress = false
    @Published private(set) var restoreInProgress = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var started = false

    var hasActiveSubscription: Bool {
        activeEntitlement != nil
    }

    func start() async {
        guard !started else {
            await refreshEntitlements()
            return
        }

        started = true
        startTransactionListener()
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await Product.products(for: Array(Self.productIDs))
            products = loaded.sorted { lhs, rhs in
                planOrder(lhs.id) < planOrder(rhs.id)
            }
        } catch {
            products = []
            errorMessage = error.localizedDescription
        }
    }

    func purchase(
        _ product: Product,
        appAccountToken: UUID
    ) async -> Bool {
        purchaseInProgress = true
        errorMessage = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase(
                options: [.appAccountToken(appAccountToken)]
            )

            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                guard Self.productIDs.contains(transaction.productID) else {
                    throw SubscriptionStoreError.unexpectedProduct
                }

                latestTransactionProof = proof(
                    from: verification,
                    transaction: transaction
                )

                await transaction.finish()
                await refreshEntitlements()
                return activeEntitlement != nil

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

    func restorePurchases() async -> Bool {
        restoreInProgress = true
        errorMessage = nil
        defer { restoreInProgress = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return activeEntitlement != nil
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshEntitlements() async {
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        var bestEntitlement: StoreSubscriptionEntitlement?
        var bestProof: AppStoreTransactionProof?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard Self.productIDs.contains(transaction.productID) else {
                continue
            }

            guard transaction.revocationDate == nil else {
                continue
            }

            if let expirationDate = transaction.expirationDate,
               expirationDate <= Date() {
                continue
            }

            let candidate = StoreSubscriptionEntitlement(
                productID: transaction.productID,
                transactionID: transaction.id,
                originalTransactionID: transaction.originalID,
                appAccountToken: transaction.appAccountToken,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate
            )

            if shouldPrefer(candidate, over: bestEntitlement) {
                bestEntitlement = candidate
                bestProof = proof(from: result, transaction: transaction)
            }
        }

        activeEntitlement = bestEntitlement

        if let bestProof {
            latestTransactionProof = bestProof
        }
    }

    func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    private func startTransactionListener() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { break }
                guard let self else { break }

                switch result {
                case .verified(let transaction):
                    guard Self.productIDs.contains(transaction.productID) else {
                        continue
                    }

                    self.latestTransactionProof = self.proof(
                        from: result,
                        transaction: transaction
                    )

                    await transaction.finish()
                    await self.refreshEntitlements()

                case .unverified:
                    self.errorMessage = SubscriptionStoreError.failedVerification.localizedDescription
                }
            }
        }
    }

    private func shouldPrefer(
        _ candidate: StoreSubscriptionEntitlement,
        over current: StoreSubscriptionEntitlement?
    ) -> Bool {
        guard let current else { return true }

        let candidateDate = candidate.expirationDate ?? candidate.purchaseDate
        let currentDate = current.expirationDate ?? current.purchaseDate
        return candidateDate > currentDate
    }

    private func proof(
        from verification: VerificationResult<Transaction>,
        transaction: Transaction
    ) -> AppStoreTransactionProof {
        AppStoreTransactionProof(
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            signedTransactionInfo: verification.jwsRepresentation
        )
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
    case unexpectedProduct

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "The App Store transaction could not be verified."
        case .unexpectedProduct:
            return "The App Store returned an unexpected subscription product."
        }
    }
}
