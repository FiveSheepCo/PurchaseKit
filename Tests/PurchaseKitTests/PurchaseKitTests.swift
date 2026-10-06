import Foundation
import StoreKit
import Testing
@testable import PurchaseKit

@MainActor
@Test func billingRetryAccessIsOptIn() {
    let manager = PurchaseManager()
    #expect(!manager.config.allowAccessDuringBillingRetry)

    let configuredManager = manager.allowAccessDuringBillingRetry()
    #expect(configuredManager === manager)
    #expect(manager.config.allowAccessDuringBillingRetry)

    manager.allowAccessDuringBillingRetry(false)
    #expect(!manager.config.allowAccessDuringBillingRetry)
}

@Test func subscriptionStatusDeterminesAccessRegardlessOfExpirationDate() {
    // A past expiration date must not override an active StoreKit status.
    let pastDate = Date(timeIntervalSince1970: 1)
    let activeState = ProductState.resolveSubscriptionState(
        for: .subscribed,
        expirationDate: pastDate
    )
    #expect(activeState.isActive)

    // A future expiration date must not override an expired StoreKit status.
    let futureDate = Date(timeIntervalSince1970: 10_000_000_000)
    let expiredState = ProductState.resolveSubscriptionState(
        for: .expired,
        expirationDate: futureDate
    )
    #expect(expiredState.isExpired)
    #expect(!expiredState.isActive)
}

@Test func gracePeriodRetainsAccessWithoutBillingRetryOptIn() {
    let expirationDate = Date(timeIntervalSince1970: 1)
    let gracePeriodExpirationDate = Date(timeIntervalSince1970: 2)
    let state = ProductState.resolveSubscriptionState(
        for: .inGracePeriod,
        expirationDate: expirationDate,
        gracePeriodExpirationDate: gracePeriodExpirationDate
    )

    #expect(state == .active(ActiveProductState(expirationDate: gracePeriodExpirationDate)))
}

@Test func billingRetryDoesNotGrantAccessUnlessEnabled() {
    let expirationDate = Date(timeIntervalSince1970: 1)
    let deniedState = ProductState.resolveSubscriptionState(
        for: .inBillingRetryPeriod,
        expirationDate: expirationDate
    )
    let allowedState = ProductState.resolveSubscriptionState(
        for: .inBillingRetryPeriod,
        expirationDate: expirationDate,
        allowAccessDuringBillingRetry: true
    )

    #expect(deniedState.isExpired)
    #expect(!deniedState.isActive)
    #expect(allowedState.isActive)
}

@Test func revocationRemainsDistinctWithoutRevocationMetadata() {
    let state = ProductState.resolveSubscriptionState(
        for: .revoked,
        expirationDate: nil,
        allowAccessDuringBillingRetry: true
    )

    #expect(state.isRevoked)
    #expect(!state.isExpired)
    #expect(!state.isActive)
}

@Test func revocationMetadataIsPreserved() {
    let revocation = RevokedProductState(
        revocationDate: Date(timeIntervalSince1970: 2),
        revocationPercentage: 100
    )
    let state = ProductState.resolveSubscriptionState(
        for: .revoked,
        expirationDate: Date(timeIntervalSince1970: 1),
        revocation: revocation
    )

    #expect(state == .revoked(revocation))
}

@Test func missingExpirationDoesNotEstablishAnExpiredState() {
    let state = ProductState.resolveSubscriptionState(
        for: .expired,
        expirationDate: nil
    )

    #expect(state == .unknown)
    #expect(!state.isActive)
    #expect(!state.isExpired)
    #expect(!state.isRevoked)
}

@Test func unrecognizedSubscriptionStateDoesNotGrantAccess() {
    let state = ProductState.resolveSubscriptionState(
        for: StoreKit::Product.SubscriptionInfo.RenewalState(rawValue: 999),
        expirationDate: Date(timeIntervalSince1970: 1),
        allowAccessDuringBillingRetry: true
    )

    #expect(state == .unknown)
    #expect(!state.isActive)
}

@MainActor
@Test func verificationPolicyAlsoAppliesToSubscriptionInformation() {
    let manager = PurchaseManager()
    let verified: VerificationResult<String> = .verified("verified")
    let unverified: VerificationResult<String> = .unverified("unverified", .invalidSignature)

    #expect(manager.resolveVerifiedValue(for: verified) == "verified")
    #expect(manager.resolveVerifiedValue(for: unverified) == nil)

    manager.allowUnverifiedTransactions()
    #expect(manager.resolveVerifiedValue(for: unverified) == "unverified")

    manager.allowUnverifiedTransactions(false)
    #expect(manager.resolveVerifiedValue(for: unverified) == nil)
}
