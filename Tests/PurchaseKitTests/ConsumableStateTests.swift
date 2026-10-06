import Foundation
import Testing
@testable import PurchaseKit

@Test func consumableTransactionsDoNotGrantPermanentAccess() {
    #expect(ProductState.resolveIAPState(for: .consumable) == .unknown)
    #expect(!ProductState.resolveIAPState(for: .consumable).isActive)
}

@Test func consumableRefundsDoNotCreatePersistentProductStates() {
    let revocation = RevokedProductState(revocationDate: Date(timeIntervalSince1970: 1))
    #expect(ProductState.resolveIAPState(for: .consumable, revocation: revocation) == .unknown)
}

@Test func knownConsumablesAreExcludedFromAccessSnapshots() {
    let snapshot = ProductStateSnapshot(productIds: ["coins", "unlock"], consumableProductIds: ["coins"])
    #expect(snapshot.resolvedStates() == ["unlock": .unknown])
}

@Test func nonConsumablePurchasesAndRefundsRetainTheirAccessStates() {
    let revocation = RevokedProductState(revocationDate: Date(timeIntervalSince1970: 1))
    #expect(ProductState.resolveIAPState(for: .nonConsumable).isActive)
    #expect(ProductState.resolveIAPState(for: .nonConsumable, revocation: revocation) == .revoked(revocation))
}
