import Foundation
import Testing
@testable import PurchaseKit

@Test func laterRefreshesCannotUndoAnObservedRevocation() {
    var cache = TransactionCache<ProductState>()
    let activeState = ProductState.active(ActiveProductState(expirationDate: nil))
    let revokedState = ProductState.revoked(RevokedProductState(revocationDate: Date(timeIntervalSince1970: 2)))
    let oldRevision = TransactionRevision(id: 1, signedDate: Date(timeIntervalSince1970: 1))
    let revokedRevision = TransactionRevision(id: 1, signedDate: Date(timeIntervalSince1970: 2), revocationDate: Date(timeIntervalSince1970: 2))

    cache.collect(activeState, revision: oldRevision)
    #expect(cache.collect(revokedState, revision: revokedRevision) == revokedState)

    // Applying a state snapshot must not remove the transaction's newer signed information
    #expect(cache.collect(activeState, revision: oldRevision) == revokedState)
    #expect(cache.values == [revokedState])
}

@Test func timestampTiesRetainRevocationsAndUpgrades() {
    let date = Date(timeIntervalSince1970: 1)
    let original = TransactionRevision(id: 1, signedDate: date)
    let revoked = TransactionRevision(id: 1, signedDate: date, revocationDate: date)
    let upgraded = TransactionRevision(id: 1, signedDate: date, isUpgraded: true)

    #expect(revoked.supersedes(original))
    #expect(!original.supersedes(revoked))
    #expect(upgraded.supersedes(original))
    #expect(!original.supersedes(upgraded))
}

@Test func newerSignedInformationCanReverseARevocation() {
    var cache = TransactionCache<String>()
    cache.collect("revoked", revision: TransactionRevision(id: 1, signedDate: Date(timeIntervalSince1970: 1), revocationDate: Date(timeIntervalSince1970: 1)))

    // A refund reversal is authoritative when StoreKit supplies newer signed information
    #expect(cache.collect("active", revision: TransactionRevision(id: 1, signedDate: Date(timeIntervalSince1970: 2))) == "active")
}

@Test func separateOwnershipSourcesHaveSeparateTransactionRecords() {
    var cache = TransactionCache<String>()
    let date = Date(timeIntervalSince1970: 1)
    cache.collect("purchased", revision: TransactionRevision(id: 1, signedDate: date))
    cache.collect("shared revoked", revision: TransactionRevision(id: 2, signedDate: date, revocationDate: date))

    #expect(Set(cache.values) == ["purchased", "shared revoked"])
}
