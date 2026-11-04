import Foundation
import StoreKit
import Testing
@testable import PurchaseKit

@Test func cachedStatesKeepTheirDetails() {
    let states: [ProductState] = [
        .active(ActiveProductState(expirationDate: nil)),
        .active(ActiveProductState(expirationDate: Date(timeIntervalSince1970: 1))),
        .expired(ExpiredProductState(expirationDate: Date(timeIntervalSince1970: 2))),
        .revoked(RevokedProductState(
            revocationDate: Date(timeIntervalSince1970: 3),
            revocationReason: .developerIssue,
            revocationPercentage: 50
        )),
    ]
    for state in states {
        #expect(CachedProductState(state)?.state == state)
    }
}

@Test func unknownStatesAreNotCached() {
    #expect(CachedProductState(.unknown) == nil)
}

@MainActor
@Test func cachedStatesAppearUntilTheFirstRefresh() throws {
    let defaults = try #require(UserDefaults(suiteName: "PurchaseKitTests.\(UUID())"))
    let unlocked = ProductState.active(ActiveProductState(expirationDate: nil))

    let firstLaunch = PurchaseManager().cacheStates(in: defaults)
    firstLaunch.publish(["unlock": unlocked, "other": .unknown])

    let secondLaunch = PurchaseManager().cacheStates(in: defaults)
    secondLaunch.loadCachedStates()
    #expect(secondLaunch.productStates == ["unlock": unlocked])

    // States from a refresh are newer than anything stored
    let refreshedLaunch = PurchaseManager().cacheStates(in: defaults)
    refreshedLaunch.stateRefreshVersion = 1
    refreshedLaunch.loadCachedStates()
    #expect(refreshedLaunch.productStates.isEmpty)
}
