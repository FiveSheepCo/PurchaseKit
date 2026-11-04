import Foundation
import Testing
@testable import PurchaseKit

@MainActor
@Test func stateUpdatesStartWithTheCurrentStatesAndFollowChanges() async {
    let unlocked = ProductState.active(ActiveProductState(expirationDate: nil))
    let manager = PurchaseManager()
    manager.publish(["unlock": .unknown])

    var updates = manager.stateUpdates.makeAsyncIterator()
    #expect(await updates.next() == ["unlock": .unknown])

    manager.publish(["unlock": unlocked])
    #expect(await updates.next() == ["unlock": unlocked])
}
