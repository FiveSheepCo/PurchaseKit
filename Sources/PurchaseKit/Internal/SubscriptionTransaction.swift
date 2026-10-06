import Foundation
import StoreKit

/// Identifies a subscription period independently of when its transaction was signed again.
struct SubscriptionTransaction {
    let id: Transaction.ID
    let originalID: UInt64
    let productID: String
    let purchaseDate: Date
    let signedDate: Date

    init(_ transaction: Transaction) {
        self.init(
            id: transaction.id,
            originalID: transaction.originalID,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            signedDate: transaction.signedDate
        )
    }

    init(id: Transaction.ID, originalID: UInt64, productID: String, purchaseDate: Date, signedDate: Date = .distantPast) {
        self.id = id
        self.originalID = originalID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.signedDate = signedDate
    }

    /// Whether this is the same period or a later purchase in the same subscription chain.
    func covers(_ other: SubscriptionTransaction) -> Bool {
        guard self.originalID == other.originalID else { return false }
        return self.id == other.id || self.purchaseDate > other.purchaseDate
    }
}
