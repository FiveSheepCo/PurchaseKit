import Foundation
import StoreKit

public struct ActiveProductState: Hashable {
    public let expirationDate: Date?

    public init(expirationDate: Date?) {
        self.expirationDate = expirationDate
    }
}

public struct ExpiredProductState: Hashable {
    public let expirationDate: Date

    public init(expirationDate: Date) {
        self.expirationDate = expirationDate
    }
}

public struct RevokedProductState: Hashable {
    /// The revocation date, if StoreKit provides it.
    public let revocationDate: Date?
    public let revocationReason: StoreKit::Transaction.RevocationReason?
    public let revocationPercentage: Decimal?

    public init(
        revocationDate: Date?,
        revocationReason: StoreKit::Transaction.RevocationReason? = nil,
        revocationPercentage: Decimal? = nil
    ) {
        self.revocationDate = revocationDate
        self.revocationReason = revocationReason
        self.revocationPercentage = revocationPercentage
    }
}

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

    static func resolveSubscriptionState(
        for renewalState: StoreKit::Product.SubscriptionInfo.RenewalState,
        expirationDate: Date?,
        gracePeriodExpirationDate: Date? = nil,
        revocation: RevokedProductState? = nil,
        allowAccessDuringBillingRetry: Bool = false
    ) -> ProductState {
        // Revocation remains distinct from expiration, even if its date is unavailable.
        if renewalState == .revoked {
            return .revoked(revocation ?? RevokedProductState(revocationDate: nil))
        }
        if let revocation {
            return .revoked(revocation)
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
