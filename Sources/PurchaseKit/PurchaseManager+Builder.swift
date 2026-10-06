import Foundation
import StoreKit

extension PurchaseManager {
    
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
    @discardableResult
    public func resolveNonRenewingSubscriptions(
        using resolver: @escaping @MainActor @Sendable (Transaction) async throws -> ProductState
    ) -> Self {
        self.config.nonRenewingSubscriptionStateResolver = resolver
        return self
    }
}
