import Foundation
import StoreKit

/// A product state as stored between launches. Unknown states are never stored.
struct CachedProductState: Codable, Equatable {
    enum Kind: String, Codable {
        case active
        case expired
        case revoked
    }

    let kind: Kind
    let expirationDate: Date?
    let revocationDate: Date?
    let revocationReason: Int?
    let revocationPercentage: Decimal?

    init?(_ state: ProductState) {
        switch state {
            case .active(let active):
                self.init(kind: .active, expirationDate: active.expirationDate)
            case .expired(let expired):
                self.init(kind: .expired, expirationDate: expired.expirationDate)
            case .revoked(let revoked):
                self.init(
                    kind: .revoked,
                    revocationDate: revoked.revocationDate,
                    revocationReason: revoked.revocationReason?.rawValue,
                    revocationPercentage: revoked.revocationPercentage
                )
            case .unknown:
                return nil
        }
    }

    private init(
        kind: Kind,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        revocationReason: Int? = nil,
        revocationPercentage: Decimal? = nil
    ) {
        self.kind = kind
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.revocationReason = revocationReason
        self.revocationPercentage = revocationPercentage
    }

    var state: ProductState {
        switch self.kind {
            case .active:
                return .active(ActiveProductState(expirationDate: self.expirationDate))
            case .expired:
                guard let expirationDate else { return .unknown }
                return .expired(ExpiredProductState(expirationDate: expirationDate))
            case .revoked:
                return .revoked(RevokedProductState(
                    revocationDate: self.revocationDate,
                    revocationReason: self.revocationReason.map(StoreKit::Transaction.RevocationReason.init(rawValue:)),
                    revocationPercentage: self.revocationPercentage
                ))
        }
    }
}
