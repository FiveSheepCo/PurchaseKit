import Foundation
import StoreKit

public struct ActiveProductState: Hashable {
    let expirationDate: Date?
}

public struct ExpiredProductState: Hashable {
    let expirationDate: Date
}

public struct RevokedProductState: Hashable {
    let revocationDate: Date
    let revocationReason: StoreKit::Transaction.RevocationReason?
    let revocationPercentage: Decimal?
}

public enum ProductState: Hashable {
    case active(ActiveProductState)
    case expired(ExpiredProductState)
    case revoked(RevokedProductState)
}

extension ProductState {
    
    /// Whether the product is currently active (not expired or revoked).
    public var isActive: Bool {
        switch self {
            case .active: true
            case .expired, .revoked: false
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
