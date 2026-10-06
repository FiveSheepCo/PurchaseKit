import Foundation
import StoreKit

extension ProductState {

    static func resolveSubscriptionState(
        for renewalState: StoreKit::Product.SubscriptionInfo.RenewalState,
        expirationDate: Date?,
        gracePeriodExpirationDate: Date? = nil,
        revocation: RevokedProductState? = nil,
        isUpgraded: Bool = false,
        allowAccessDuringBillingRetry: Bool = false
    ) -> ProductState {
        // Revocation remains distinct from expiration, even if its date is unavailable
        if renewalState == .revoked {
            return .revoked(revocation ?? RevokedProductState(revocationDate: nil))
        }
        if let revocation {
            return .revoked(revocation)
        }

        // An upgraded transaction no longer grants access to the previous product
        if isUpgraded {
            guard let expirationDate else { return .unknown }
            return .expired(ExpiredProductState(expirationDate: expirationDate))
        }

        switch renewalState {
            case .subscribed:
                return .active(ActiveProductState(expirationDate: expirationDate))
            case .inGracePeriod:
                let accessExpirationDate = gracePeriodExpirationDate ?? expirationDate
                return .active(ActiveProductState(expirationDate: accessExpirationDate))
            case .inBillingRetryPeriod where allowAccessDuringBillingRetry:
                return .active(ActiveProductState(expirationDate: expirationDate))
            case .expired, .inBillingRetryPeriod:
                guard let expirationDate else { return .unknown }
                return .expired(ExpiredProductState(expirationDate: expirationDate))
            default:
                return .unknown
        }
    }

    /// Preserve current access when additional subscription status information is unavailable.
    static func resolveSubscriptionFallback(
        hasCurrentEntitlement: Bool,
        expirationDate: Date?,
        revocation: RevokedProductState? = nil,
        isUpgraded: Bool = false
    ) -> ProductState {
        if let revocation { return .revoked(revocation) }
        if isUpgraded {
            return expirationDate.map { .expired(ExpiredProductState(expirationDate: $0)) } ?? .unknown
        }
        guard hasCurrentEntitlement else { return .unknown }

        // The paid period may have ended while access continues in an unqueried grace period
        return .active(ActiveProductState(expirationDate: nil))
    }
}
