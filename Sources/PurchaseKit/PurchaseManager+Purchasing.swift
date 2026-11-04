import Foundation
import StoreKit

extension PurchaseManager {

    /// Purchase a product and deliver its transaction.
    ///
    /// In SwiftUI, prefer the `purchase` environment action, which presents the confirmation
    /// in the right scene, and pass its result to `process(_:)`.
    @discardableResult
    public func purchase(
        _ product: Product,
        options: Set<StoreKit::Product.PurchaseOption> = []
    ) async throws -> PurchaseOutcome {
        let result = try await product.skProduct.purchase(options: options)
        return await self.process(result)
    }

    /// Deliver the transaction of a purchase made in this app.
    ///
    /// StoreKit returns these through the purchase result instead of the transaction updates sequence.
    @discardableResult
    public func process(_ result: StoreKit::Product.PurchaseResult) async -> PurchaseOutcome {
        switch result {
            case .success(let verificationResult):
                await self.process(verificationResult)
                switch verificationResult {
                    case .verified(let transaction):
                        return .purchased(transaction)
                    case .unverified(let transaction, let error):
                        return self.config.allowUnverifiedTransactions ? .purchased(transaction) : .unverified(error)
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                // Anything that did complete still arrives through the transaction updates
                self.logger.error("Unknown purchase result: \(String(describing: result))")
                return .cancelled
        }
    }

    /// Sync purchases with the App Store, then refresh product states.
    ///
    /// Call this only from an explicit Restore Purchases action: it may ask the customer to sign in.
    public func restore() async throws {
        try await AppStore.sync()
        await self.refresh()
    }
}
