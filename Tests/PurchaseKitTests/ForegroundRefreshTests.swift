import Foundation
import Testing
@testable import PurchaseKit

@MainActor
@Test func theManagerRefreshesEachTimeTheAppReturns() async {
    let name = Notification.Name("PurchaseKitTests.foreground.\(UUID())")
    let manager = PurchaseManager()
    let (refreshes, continuation) = AsyncStream.makeStream(of: Void.self)
    manager.setupForegroundRefreshTask(observing: name) { continuation.yield() }
    var iterator = refreshes.makeAsyncIterator()

    // The listener starts on its own task, so keep returning until it has heard two of them
    let app = Task {
        while !Task.isCancelled {
            NotificationCenter.default.post(name: name, object: nil)
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
    await iterator.next()
    await iterator.next()
    app.cancel()
}

@MainActor
@Test func refreshingOnForegroundIsOnByDefault() {
    let manager = PurchaseManager()
    manager.setup().apply()
    #expect(manager.config.refreshesOnForeground)

    let optedOut = PurchaseManager()
    optedOut.setup().refreshOnForeground(false).apply()
    #expect(!optedOut.config.refreshesOnForeground)
}
