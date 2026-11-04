import Foundation
import Testing
@testable import PurchaseKit

private enum AppEntitlement: Entitlement {
    case pro
    case founder
}

private enum OtherEntitlement: Entitlement {
    case pro
}

@MainActor
private func manager(_ configure: (PurchaseManager.Setup<AppEntitlement>) -> PurchaseManager.Setup<AppEntitlement>) -> PurchaseManager {
    let manager = PurchaseManager()
    configure(manager.setup(entitlements: AppEntitlement.self)).apply()
    return manager
}

private let permanent = ProductState.active(ActiveProductState(expirationDate: nil))
private let expiringSoon = ProductState.active(ActiveProductState(expirationDate: Date(timeIntervalSince1970: 10)))
private let expiringLater = ProductState.active(ActiveProductState(expirationDate: Date(timeIntervalSince1970: 20)))
private let expiredEarlier = ProductState.expired(ExpiredProductState(expirationDate: Date(timeIntervalSince1970: 1)))
private let expiredLater = ProductState.expired(ExpiredProductState(expirationDate: Date(timeIntervalSince1970: 2)))
private let revokedLater = ProductState.revoked(RevokedProductState(revocationDate: Date(timeIntervalSince1970: 2)))

@MainActor
@Test func anyActiveProductGrantsItsEntitlement() {
    let manager = manager {
        $0.add(subscription: "pro_monthly", grants: .pro)
            .add(iap: "pro_lifetime", grants: .pro)
    }
    manager.publish(["pro_monthly": expiredEarlier, "pro_lifetime": permanent])

    #expect(manager.isActive(AppEntitlement.pro))
    #expect(manager.state(of: AppEntitlement.pro) == permanent)
    #expect(!manager.isActive(AppEntitlement.founder))
}

@MainActor
@Test func entitlementsOfDifferentTypesNeverCollide() {
    let manager = manager { $0.add(iap: "pro_lifetime", grants: .pro) }
    manager.publish(["pro_lifetime": permanent])

    #expect(manager.isActive(AppEntitlement.pro))
    #expect(!manager.isActive(OtherEntitlement.pro))
}

@MainActor
@Test func existentialEntitlementsResolveLikeConcreteOnes() {
    let manager = manager { $0.add(iap: "founders_pack", grants: .founder) }
    manager.publish(["founders_pack": permanent])

    let entitlement: any Entitlement = AppEntitlement.founder
    #expect(manager.isActive(entitlement))
}

@MainActor
@Test func productsGrantingSeveralEntitlementsRegisterOnce() {
    let manager = manager {
        $0.add(iap: "bundle", grants: .pro, .founder)
            .add(iap: "bundle")
    }
    manager.publish(["bundle": permanent])

    #expect(manager.registeredProducts.map(\.id) == ["bundle"])
    #expect(manager.isActive(AppEntitlement.pro))
    #expect(manager.isActive(AppEntitlement.founder))
}

@Test func theLongestAccessWins() {
    #expect(ProductState.combinedState(from: [expiringSoon, permanent, expiringLater]) == permanent)
    #expect(ProductState.combinedState(from: [expiringLater, expiringSoon]) == expiringLater)
    #expect(ProductState.combinedState(from: [expiringSoon, expiringLater]) == expiringLater)
}

@Test func withoutAccessTheMostRecentEndWins() {
    #expect(ProductState.combinedState(from: [expiredLater, .unknown, expiredEarlier]) == expiredLater)
    #expect(ProductState.combinedState(from: [revokedLater, expiredLater]) == revokedLater)
    #expect(ProductState.combinedState(from: [expiredLater, revokedLater]) == revokedLater)
}

@Test func entitlementsWithoutKnownStatesAreUnknown() {
    #expect(ProductState.combinedState(from: []) == .unknown)
    #expect(ProductState.combinedState(from: [.unknown, .unknown]) == .unknown)
}

@MainActor
@Test func typedEntitlementsAcceptShorthandCases() {
    let manager = manager { $0.add(iap: "founders_pack", grants: .founder) }
    manager.publish(["founders_pack": permanent])
    let entitlements = manager.entitlements(AppEntitlement.self)

    #expect(entitlements.isActive(.founder))
    #expect(entitlements.state(of: .pro) == .unknown)
    #expect(entitlements.products(granting: .founder).isEmpty)
}

@MainActor
@Test func setupReachesTheManagerOnlyWhenApplied() {
    let manager = PurchaseManager()
    let setup = manager.setup(entitlements: AppEntitlement.self)
        .add(iap: "founders_pack", grants: .founder)
        .allowAccessDuringBillingRetry()
    #expect(manager.registeredProducts.isEmpty)
    #expect(!manager.config.allowAccessDuringBillingRetry)

    setup.apply()
    #expect(manager.registeredProducts.map(\.id) == ["founders_pack"])
    #expect(manager.config.allowAccessDuringBillingRetry)
}

@MainActor
@Test func appsWithoutEntitlementsRegisterPlainProducts() {
    let manager = PurchaseManager()
    manager.setup().add(iap: "unlock").add(subscription: "pro_monthly").apply()
    #expect(manager.registeredProducts.map(\.id) == ["unlock", "pro_monthly"])
}
