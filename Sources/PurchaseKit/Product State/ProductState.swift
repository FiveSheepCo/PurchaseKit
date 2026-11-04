import Foundation
import StoreKit

public enum ProductState: Hashable, Sendable {
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
}
