import Foundation
import StoreKit
import Testing
@testable import PurchaseKit

private struct OfflineError: Error {}

@MainActor
private func manager() -> PurchaseManager {
    let manager = PurchaseManager()
    manager.setup().add(iap: "unlock").apply()
    return manager
}

@MainActor
@Test func productsAreNotLoadedBeforeTheFirstFetch() {
    #expect(manager().productsStatus == .notLoaded)
}

@MainActor
@Test func productsAreLoadingWhileTheFetchRuns() async throws {
    let manager = manager()
    var statusDuringFetch: ProductsStatus?
    try await manager.fetchProducts { _ in
        statusDuringFetch = manager.productsStatus
        return []
    }
    #expect(statusDuringFetch == .loading)
    #expect(manager.productsStatus == .loaded)
}

@MainActor
@Test func aFailedFetchIsReported() async {
    let manager = manager()
    await #expect(throws: OfflineError.self) {
        try await manager.fetchProducts { _ in throw OfflineError() }
    }
    #expect(manager.productsStatus == .failed)
}

@MainActor
@Test func aLaterFetchRecoversFromAFailure() async throws {
    let manager = manager()
    try? await manager.fetchProducts { _ in throw OfflineError() }
    try await manager.fetchProducts { _ in [] }
    #expect(manager.productsStatus == .loaded)
}

@MainActor
@Test func theFetchAsksForEveryRegisteredProduct() async throws {
    let manager = PurchaseManager()
    manager.setup().add(iap: "unlock").add(subscription: "pro_monthly").apply()
    var requested: [String] = []
    try await manager.fetchProducts { ids in
        requested = ids
        return []
    }
    #expect(Set(requested) == ["unlock", "pro_monthly"])
}
