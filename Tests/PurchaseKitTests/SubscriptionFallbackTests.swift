import Foundation
import Testing
@testable import PurchaseKit

@Test func statusLookupFailurePreservesVerifiedCurrentAccess() {
    let state = ProductState.resolveSubscriptionFallback(
        hasCurrentEntitlement: true,
        expirationDate: Date(timeIntervalSince1970: 10_000_000_000)
    )

    #expect(state.isActive)
}

@Test func currentGracePeriodAccessSurvivesUnavailableStatusInformation() {
    let state = ProductState.resolveSubscriptionFallback(
        hasCurrentEntitlement: true,
        expirationDate: Date(timeIntervalSince1970: 1)
    )

    // A past paid-period expiration does not establish the end of a current grace period
    #expect(state == .active(ActiveProductState(expirationDate: nil)))
}

@Test func historicalSubscriptionsDoNotEstablishCurrentAccess() {
    let state = ProductState.resolveSubscriptionFallback(
        hasCurrentEntitlement: false,
        expirationDate: Date(timeIntervalSince1970: 10_000_000_000)
    )

    #expect(state == .unknown)
}

@Test func newerRevocationsAndUpgradesOverrideCurrentEntitlementFallbacks() {
    let expirationDate = Date(timeIntervalSince1970: 10_000_000_000)
    let revocation = RevokedProductState(revocationDate: Date(timeIntervalSince1970: 2))
    #expect(ProductState.resolveSubscriptionFallback(
        hasCurrentEntitlement: true,
        expirationDate: expirationDate,
        revocation: revocation
    ).isRevoked)
    #expect(ProductState.resolveSubscriptionFallback(
        hasCurrentEntitlement: true,
        expirationDate: expirationDate,
        isUpgraded: true
    ).isExpired)
}
