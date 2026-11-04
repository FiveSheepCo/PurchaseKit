import Foundation
import StoreKit

public struct RevokedProductState: Hashable, Sendable {
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
