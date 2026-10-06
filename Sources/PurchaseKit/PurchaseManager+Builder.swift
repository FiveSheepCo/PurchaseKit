import Foundation

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
    
    /// Allow unverified transactions to be handled.
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
}
