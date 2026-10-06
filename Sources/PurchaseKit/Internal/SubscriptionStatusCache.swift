import Foundation
import StoreKit

/// The transaction period and signed renewal information associated with a status.
struct SubscriptionStatusVersion {
    let transaction: SubscriptionTransaction
    let signedDate: Date
    let state: StoreKit::Product.SubscriptionInfo.RenewalState

    /// A status must cover both the transaction period and any newer signed metadata.
    func covers(_ other: SubscriptionTransaction) -> Bool {
        guard self.transaction.covers(other) else { return false }
        guard self.transaction.id == other.id else { return true }
        return max(self.transaction.signedDate, self.signedDate) >= other.signedDate
    }

    func supersedes(_ other: SubscriptionStatusVersion, fromUpdate: Bool, previousFromUpdate: Bool) -> Bool {
        if self.transaction.id != other.transaction.id {
            return self.transaction.covers(other.transaction)
        }
        if self.signedDate != other.signedDate {
            return self.signedDate > other.signedDate
        }
        // A delivered status update wins a tie with a previously queried status
        return fromUpdate || !previousFromUpdate || self.state == other.state
    }
}

/// Retains verified status updates when later queries return older renewal information.
struct SubscriptionStatusCache<Value> {
    private struct Entry {
        let value: Value
        let version: SubscriptionStatusVersion
        let fromUpdate: Bool
    }

    private var entries: [UInt64: Entry] = [:]

    var values: [Value] {
        self.entries.values.map(\.value)
    }

    @discardableResult
    mutating func collect(_ value: Value, version: SubscriptionStatusVersion, fromUpdate: Bool = false) -> Value {
        let originalId = version.transaction.originalID
        let existingEntry = self.entries[originalId]
        if let existingEntry,
           !version.supersedes(existingEntry.version, fromUpdate: fromUpdate, previousFromUpdate: existingEntry.fromUpdate) {
            return existingEntry.value
        }
        let retainsUpdate = existingEntry.map {
            $0.fromUpdate && $0.version.transaction.id == version.transaction.id && $0.version.signedDate == version.signedDate
        } ?? false
        self.entries[originalId] = Entry(value: value, version: version, fromUpdate: fromUpdate || retainsUpdate)
        return value
    }
}
