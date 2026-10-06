import Foundation
import StoreKit

public enum ProductState: Hashable {
    case active(ActiveProductState)
    case expired(ExpiredProductState)
    case revoked(RevokedProductState)
    /// The customer's current entitlement could not be established.
    case unknown
}

extension ProductState {
    
    /// Whether the product is currently known to be active.
    public var isActive: Bool {
        switch self {
            case .active: true
            case .expired, .revoked, .unknown: false
        }
    }
    
    /// Whether the product is expired.
    /// This does not include revoked products.
    public var isExpired: Bool {
        switch self {
            case .expired: true
            default: false
        }
    }
    
    /// Whether the product is revoked.
    /// This does not include expired products.
    public var isRevoked: Bool {
        switch self {
            case .revoked: true
            default: false
        }
    }
}

extension ProductState {

    static func preferredState(from states: [ProductState]) -> ProductState {
        // A valid entitlement takes precedence over another expired or revoked ownership source
        if let activeState = states.first(where: \.isActive) {
            return activeState
        }
        if states.contains(.unknown) {
            return .unknown
        }
        return states.first ?? .unknown
    }

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
}
