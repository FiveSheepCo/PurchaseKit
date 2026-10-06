import Foundation
import StoreKit
import Testing
@testable import PurchaseKit

private func subscriptionPeriod(id: UInt64, originalID: UInt64 = 1, productID: String = "subscription", purchaseDate: TimeInterval) -> SubscriptionTransaction {
    SubscriptionTransaction(id: id, originalID: originalID, productID: productID, purchaseDate: Date(timeIntervalSince1970: purchaseDate))
}

@Test func anOlderStatusDoesNotCoverANewerRenewal() {
    let previousPeriod = subscriptionPeriod(id: 1, purchaseDate: 1)
    let renewal = subscriptionPeriod(id: 2, purchaseDate: 2)

    #expect(!previousPeriod.covers(renewal))
    #expect(renewal.covers(previousPeriod))
    #expect(renewal.covers(renewal))
}

@Test func statusMatchingKeepsOwnershipSourcesIndependent() {
    let purchased = subscriptionPeriod(id: 1, purchaseDate: 1)
    let shared = subscriptionPeriod(id: 2, originalID: 2, purchaseDate: 2)

    #expect(!shared.covers(purchased))
    #expect(!purchased.covers(shared))
}

@Test func reSignedOldPeriodsCannotReplaceNewerSubscriptionStatuses() {
    var cache = SubscriptionStatusCache<String>()
    let renewal = SubscriptionStatusVersion(transaction: subscriptionPeriod(id: 2, purchaseDate: 2), signedDate: Date(timeIntervalSince1970: 2), state: .subscribed)
    let previousPeriod = SubscriptionStatusVersion(transaction: subscriptionPeriod(id: 1, purchaseDate: 1), signedDate: Date(timeIntervalSince1970: 3), state: .expired)
    cache.collect("renewed", version: renewal)

    #expect(cache.collect("expired previous period", version: previousPeriod) == "renewed")
}

@Test func endOfGracePeriodUpdatesSurviveOlderStatusQueries() {
    var cache = SubscriptionStatusCache<String>()
    let period = subscriptionPeriod(id: 1, purchaseDate: 1)
    let date = Date(timeIntervalSince1970: 1)
    let gracePeriod = SubscriptionStatusVersion(transaction: period, signedDate: date, state: .inGracePeriod)
    let expired = SubscriptionStatusVersion(transaction: period, signedDate: date, state: .expired)
    cache.collect("grace period", version: gracePeriod)
    cache.collect("expired", version: expired, fromUpdate: true)

    // A state change need not create a new transaction or change its signed renewal timestamp
    #expect(cache.collect("stale grace period", version: gracePeriod) == "expired")
    #expect(cache.collect("confirmed expired", version: expired) == "confirmed expired")
    #expect(cache.collect("stale grace period", version: gracePeriod) == "confirmed expired")
}

@Test func statusQueriesCanObserveExpirationWithoutATransactionChange() {
    var cache = SubscriptionStatusCache<String>()
    let period = subscriptionPeriod(id: 1, purchaseDate: 1)
    let date = Date(timeIntervalSince1970: 1)
    cache.collect("subscribed", version: SubscriptionStatusVersion(transaction: period, signedDate: date, state: .subscribed))

    #expect(cache.collect("expired", version: SubscriptionStatusVersion(transaction: period, signedDate: date, state: .expired)) == "expired")
}

@Test func laterRenewalInformationCanRecoverFromBillingRetry() {
    var cache = SubscriptionStatusCache<String>()
    let period = subscriptionPeriod(id: 1, purchaseDate: 1)
    cache.collect("billing retry", version: SubscriptionStatusVersion(transaction: period, signedDate: Date(timeIntervalSince1970: 1), state: .inBillingRetryPeriod), fromUpdate: true)

    #expect(cache.collect("recovered", version: SubscriptionStatusVersion(transaction: period, signedDate: Date(timeIntervalSince1970: 2), state: .subscribed)) == "recovered")
}

@Test func aLaterStatusUpdateCanRestoreAccessOnATimestampTie() {
    var cache = SubscriptionStatusCache<String>()
    let period = subscriptionPeriod(id: 1, purchaseDate: 1)
    let date = Date(timeIntervalSince1970: 1)
    cache.collect("revoked", version: SubscriptionStatusVersion(transaction: period, signedDate: date, state: .revoked), fromUpdate: true)

    #expect(cache.collect("restored", version: SubscriptionStatusVersion(transaction: period, signedDate: date, state: .subscribed), fromUpdate: true) == "restored")
}

@Test func olderStatusMetadataDoesNotOverrideARefundReversal() {
    let period = SubscriptionTransaction(id: 1, originalID: 1, productID: "subscription", purchaseDate: Date(timeIntervalSince1970: 1), signedDate: Date(timeIntervalSince1970: 1))
    let restored = SubscriptionTransaction(id: 1, originalID: 1, productID: "subscription", purchaseDate: Date(timeIntervalSince1970: 1), signedDate: Date(timeIntervalSince1970: 3))
    let revokedStatus = SubscriptionStatusVersion(transaction: period, signedDate: Date(timeIntervalSince1970: 2), state: .revoked)

    #expect(!revokedStatus.covers(restored))
}
