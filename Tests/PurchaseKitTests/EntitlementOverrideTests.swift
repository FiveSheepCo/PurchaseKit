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

private let permanent = ProductState.active(ActiveProductState(expirationDate: nil))
private let expiring = ProductState.active(ActiveProductState(expirationDate: Date(timeIntervalSince1970: 10)))

private func freshDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "PurchaseKitTests.\(UUID())"))
}

@MainActor
private func manager(overridesIn defaults: UserDefaults?) -> PurchaseManager {
    let manager = PurchaseManager()
    var setup = manager.setup(entitlements: AppEntitlement.self)
        .add(iap: "pro_lifetime", grants: .pro)
        .add(iap: "founders_pack", grants: .founder)
    if let defaults { setup = setup.allowEntitlementOverrides(in: defaults) }
    setup.apply()
    return manager
}

@MainActor
@Test func anOverrideGrantsAnEntitlementWithoutAPurchase() throws {
    let manager = manager(overridesIn: try freshDefaults())
    let entitlements = manager.entitlements(AppEntitlement.self)

    entitlements.setOverride(.founder, isActive: true)

    #expect(entitlements.isActive(.founder))
    #expect(entitlements.state(of: .founder) == permanent)
    #expect(!entitlements.isActive(.pro))
    // Product states stay what StoreKit says
    #expect(manager.state(for: "founders_pack") == .unknown)
}

@MainActor
@Test func anOverrideWithholdsAPurchasedEntitlement() throws {
    let manager = manager(overridesIn: try freshDefaults())
    let entitlements = manager.entitlements(AppEntitlement.self)
    manager.publish(["pro_lifetime": permanent])

    entitlements.setOverride(.pro, isActive: false)
    #expect(!entitlements.isActive(.pro))

    entitlements.setOverride(.pro, isActive: nil)
    #expect(entitlements.isActive(.pro))
    #expect(entitlements.override(for: .pro) == nil)
}

@MainActor
@Test func grantingKeepsTheRealStateOfAnActiveEntitlement() throws {
    let manager = manager(overridesIn: try freshDefaults())
    let entitlements = manager.entitlements(AppEntitlement.self)
    manager.publish(["pro_lifetime": expiring])

    entitlements.setOverride(.pro, isActive: true)

    #expect(entitlements.state(of: .pro) == expiring)
}

@MainActor
@Test func overridesAreRememberedBetweenLaunches() throws {
    let defaults = try freshDefaults()
    manager(overridesIn: defaults).entitlements(AppEntitlement.self).setOverride(.founder, isActive: true)

    let relaunched = manager(overridesIn: defaults).entitlements(AppEntitlement.self)

    #expect(relaunched.override(for: .founder) == true)
    #expect(relaunched.isActive(.founder))
}

@MainActor
@Test func overridesOfDifferentTypesNeverCollide() throws {
    let manager = manager(overridesIn: try freshDefaults())
    manager.setOverride(AppEntitlement.pro, isActive: true)

    #expect(manager.isActive(AppEntitlement.pro))
    #expect(!manager.isActive(OtherEntitlement.pro))
}

@MainActor
@Test func storedOverridesAreIgnoredUnlessAllowed() throws {
    let defaults = try freshDefaults()
    manager(overridesIn: defaults).entitlements(AppEntitlement.self).setOverride(.founder, isActive: true)

    // A release build that doesn't allow overrides sees only real purchases
    let release = PurchaseManager()
    release.setup(entitlements: AppEntitlement.self).add(iap: "founders_pack", grants: .founder).cacheStates(in: defaults).apply()

    #expect(!release.isActive(AppEntitlement.founder))
}

@MainActor
@Test func streamConsumersHearAboutOverrides() async throws {
    let manager = manager(overridesIn: try freshDefaults())
    var updates = manager.stateUpdates.makeAsyncIterator()
    _ = await updates.next()

    manager.setOverride(AppEntitlement.founder, isActive: true)

    #expect(await updates.next() != nil)
    #expect(manager.isActive(AppEntitlement.founder))
}
