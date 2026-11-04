import Foundation
import StoreKit

/// The result of a purchase as the app should present it.
public enum PurchaseOutcome: Sendable {
    /// The purchase succeeded and the transaction was handed to delivery.
    case purchased(Transaction)
    /// The purchase awaits approval, such as Ask to Buy. The transaction arrives later as an update.
    case pending
    /// The customer cancelled the purchase.
    case cancelled
    /// StoreKit could not verify the transaction, so it grants nothing.
    case unverified(VerificationResult<Transaction>.VerificationError)
}
