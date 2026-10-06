import Foundation
import StoreKit

extension PurchaseManager {

    /// Handle transactions before marking them as finished in StoreKit.
    ///
    /// Return only after delivering or reconciling the purchased content durably.
    /// Throw to leave the transaction unfinished; `refresh()` retries unfinished transactions.
    /// Without a handler, transactions remain unfinished.
    ///
    /// Use the transaction's `id` to make delivery idempotent across retries and app launches.
    /// For consumables, persist the delivered `purchasedQuantity` with the transaction ID.
    /// Handle refunds and revocations without delivering the purchased content again.
    @discardableResult
    public func handleTransactions(
        using handler: @escaping @MainActor @Sendable (Transaction) async throws -> Void
    ) -> Self {
        self.config.transactionHandler = handler
        return self
    }
    
    @discardableResult
    public func add(iap id: String) -> Self {
        registeredProducts.append(RegisteredProduct(id: id, kind: .iap))
        return self
    }
    
    @discardableResult
    public func add(subscription id: String) -> Self {
        registeredProducts.append(RegisteredProduct(id: id, kind: .subscription))
        return self
    }
    
    /// Allow unverified transactions and subscription renewal information to be handled.
    ///
    /// - Warning: This is highly discouraged and should never be done in production environments!
    @discardableResult
    public func allowUnverifiedTransactions(_ enabled: Bool = true) -> Self {
        self.config.allowUnverifiedTransactions = enabled
        return self
    }
    
    /// Allow accessing products during billing retry.
    @discardableResult
    public func allowAccessDuringBillingRetry(_ enabled: Bool = true) -> Self {
        self.config.allowAccessDuringBillingRetry = enabled
        return self
    }

    /// Resolve non-renewing subscription states using the app's entitlement policy.
    ///
    /// Use trusted server data to determine expiration independently of the device clock.
    /// Without a resolver, non-renewing subscriptions have an unknown state.
    /// The policy is rechecked every minute while the manager is running.
    @discardableResult
    public func resolveNonRenewingSubscriptions(
        using resolver: @escaping @MainActor @Sendable (Transaction) async throws -> ProductState
    ) -> Self {
        self.config.nonRenewingSubscriptionStateResolver = resolver
        if self.updateTask != nil {
            self.setupNonRenewingSubscriptionUpdateTask()
        }
        return self
    }
}
