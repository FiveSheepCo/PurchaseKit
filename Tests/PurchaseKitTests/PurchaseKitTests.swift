import Foundation
import StoreKit
import Testing
@testable import PurchaseKit

@MainActor
@Test func billingRetryAccessIsOptIn() {
    let manager = PurchaseManager()
    #expect(!manager.config.allowAccessDuringBillingRetry)
    #expect(!manager.setup().allowAccessDuringBillingRetry().allowAccessDuringBillingRetry(false).config.allowAccessDuringBillingRetry)

    manager.setup().allowAccessDuringBillingRetry().apply()
    #expect(manager.config.allowAccessDuringBillingRetry)
}

@Test func subscriptionStatusDeterminesAccessRegardlessOfExpirationDate() {
    // A past expiration date must not override an active StoreKit status
    let pastDate = Date(timeIntervalSince1970: 1)
    let activeState = ProductState.resolveSubscriptionState(
        for: .subscribed,
        expirationDate: pastDate
    )
    #expect(activeState.isActive)

    // A future expiration date must not override an expired StoreKit status
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

    manager.config.allowUnverifiedTransactions = true
    #expect(manager.resolveVerifiedValue(for: unverified) == "unverified")

    manager.config.allowUnverifiedTransactions = false
    #expect(manager.resolveVerifiedValue(for: unverified) == nil)
}

@Test func losingSharedAccessDoesNotRemovePurchasedAccess() {
    let activeState = ProductState.active(ActiveProductState(expirationDate: Date(timeIntervalSince1970: 3)))
    let revokedState = ProductState.revoked(RevokedProductState(revocationDate: Date(timeIntervalSince1970: 2)))

    #expect(ProductState.preferredState(from: [revokedState, activeState]) == activeState)
    #expect(ProductState.preferredState(from: [activeState, revokedState]) == activeState)

    // Access is removed after the remaining ownership source also expires
    let expiredState = ProductState.expired(ExpiredProductState(expirationDate: Date(timeIntervalSince1970: 3)))
    #expect(!ProductState.preferredState(from: [expiredState, revokedState]).isActive)
}

@Test func gracePeriodAndOptedInBillingRetrySurviveAnotherRevokedEntitlement() {
    let revokedState = ProductState.revoked(RevokedProductState(revocationDate: nil))
    for renewalState in [StoreKit::Product.SubscriptionInfo.RenewalState.inGracePeriod, .inBillingRetryPeriod] {
        let state = ProductState.resolveSubscriptionState(
            for: renewalState,
            expirationDate: Date(timeIntervalSince1970: 1),
            allowAccessDuringBillingRetry: true
        )
        #expect(ProductState.preferredState(from: [revokedState, state]).isActive)
    }
}

@Test func uncertainEntitlementsDoNotOverrideVerifiedAccess() {
    let activeState = ProductState.active(ActiveProductState(expirationDate: nil))
    let expiredState = ProductState.expired(ExpiredProductState(expirationDate: Date(timeIntervalSince1970: 1)))

    #expect(ProductState.preferredState(from: [.unknown, activeState]) == activeState)
    #expect(ProductState.preferredState(from: [.unknown, expiredState]) == .unknown)
    #expect(ProductState.preferredState(from: []) == .unknown)
}

@Test func upgradedTransactionsDoNotRetainAccessFromCachedStatus() {
    let state = ProductState.resolveSubscriptionState(
        for: .subscribed,
        expirationDate: Date(timeIntervalSince1970: 10_000_000_000),
        isUpgraded: true
    )

    #expect(state.isExpired)
    #expect(!state.isActive)
}

@Test func newerRevocationInformationOverridesCachedActiveStatus() {
    let revocation = RevokedProductState(revocationDate: Date(timeIntervalSince1970: 2))
    let state = ProductState.resolveSubscriptionState(
        for: .subscribed,
        expirationDate: Date(timeIntervalSince1970: 3),
        revocation: revocation
    )

    #expect(state == .revoked(revocation))
    #expect(!state.isActive)
}

@MainActor
@Test func nonRenewingPolicyTaskDoesNotRetainTheManager() async {
    var manager: PurchaseManager? = PurchaseManager()
    weak let weakManager = manager
    manager?.setup().resolveNonRenewingSubscriptions { _ in .unknown }.apply()
    manager?.setupNonRenewingSubscriptionUpdateTask()
    let updateTask = manager?.nonRenewingSubscriptionUpdateTask

    // Allow the task to enter its sleep before releasing the manager
    await Task.yield()
    manager = nil

    #expect(weakManager == nil)
    #expect(updateTask?.isCancelled == true)
}

@MainActor
@Test func overlappingRefreshesCannotRestoreStaleAccess() {
    let manager = PurchaseManager()
    let activeState = ProductState.active(ActiveProductState(expirationDate: nil))
    let revokedState = ProductState.revoked(RevokedProductState(revocationDate: nil))
    manager.productStates = ["subscription": activeState]
    manager.stateRefreshVersion = 2

    // The latest refresh removes access before an older refresh finishes
    manager.applyProductStates(["subscription": revokedState], refreshVersion: 2)
    manager.applyProductStates(["subscription": activeState], refreshVersion: 1)

    #expect(manager.productStates["subscription"] == revokedState)
}

@MainActor
@Test func overlappingRefreshesCannotDiscardNewAccess() {
    let manager = PurchaseManager()
    let activeState = ProductState.active(ActiveProductState(expirationDate: nil))
    manager.stateRefreshVersion = 2

    // An older startup snapshot must not erase access granted by a purchase update
    manager.applyProductStates([:], refreshVersion: 1)
    manager.applyProductStates(["subscription": activeState], refreshVersion: 2)

    #expect(manager.productStates["subscription"] == activeState)
}
