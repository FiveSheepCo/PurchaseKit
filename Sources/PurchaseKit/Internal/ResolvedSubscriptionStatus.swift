import Foundation
import StoreKit

/// Subscription status information accepted by the manager's verification policy.
struct ResolvedSubscriptionStatus {
    let transaction: Transaction
    let state: StoreKit::Product.SubscriptionInfo.RenewalState
    let gracePeriodExpirationDate: Date?
    let signedDate: Date
    let isVerified: Bool

    var version: SubscriptionStatusVersion {
        SubscriptionStatusVersion(transaction: SubscriptionTransaction(self.transaction), signedDate: self.signedDate, state: self.state)
    }

    var removesAccess: Bool {
        self.state == .revoked || self.state == .expired || self.state == .inBillingRetryPeriod
    }
}
