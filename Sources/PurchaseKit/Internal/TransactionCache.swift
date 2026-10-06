import Foundation
import StoreKit

/// Retains the newest verified version of each transaction across entitlement refreshes.
struct TransactionCache<Value> {
    private struct Entry {
        let value: Value
        let revision: TransactionRevision
    }

    private var entries: [Transaction.ID: Entry] = [:]

    var values: [Value] {
        self.entries.values.map(\.value)
    }

    @discardableResult
    mutating func collect(_ value: Value, revision: TransactionRevision) -> Value {
        if let existingEntry = self.entries[revision.id],
           !revision.supersedes(existingEntry.revision) {
            return existingEntry.value
        }
        self.entries[revision.id] = Entry(value: value, revision: revision)
        return value
    }
}

extension TransactionRevision {

    /// Prefer newer signed information, retaining revocations and upgrades on a timestamp tie.
    func supersedes(_ other: TransactionRevision) -> Bool {
        if self.signedDate != other.signedDate {
            return self.signedDate > other.signedDate
        }
        if (self.revocationDate != nil) != (other.revocationDate != nil) {
            return self.revocationDate != nil
        }
        if self.isUpgraded != other.isUpgraded {
            return self.isUpgraded
        }
        return true
    }
}
