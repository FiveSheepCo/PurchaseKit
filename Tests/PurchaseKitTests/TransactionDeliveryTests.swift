import Foundation
import Testing
@testable import PurchaseKit

@MainActor
private final class DeliveryProbe {
    var events: [String] = []
    var continuation: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { self.continuation = $0 }
    }

    func resume() {
        self.continuation?.resume()
        self.continuation = nil
    }
}

private enum DeliveryError: Error {
    case unavailable
}

@MainActor
@Test func deliveryFinishesOnlyAfterTheHandlerSucceeds() async throws {
    let delivery = TransactionDelivery()
    let probe = DeliveryProbe()
    let revision = TransactionRevision(id: 1, signedDate: Date())

    try await delivery.deliver(
        revision: revision,
        using: { probe.events.append("delivered") },
        finish: { probe.events.append("finished") }
    )

    #expect(probe.events == ["delivered", "finished"])
}

@MainActor
@Test func missingHandlerLeavesTheTransactionUnfinished() async throws {
    let probe = DeliveryProbe()
    try await TransactionDelivery().deliver(
        revision: TransactionRevision(id: 1, signedDate: Date()),
        using: nil,
        finish: { probe.events.append("finished") }
    )

    #expect(probe.events.isEmpty)
}

@MainActor
@Test func failedDeliveryRemainsRetryable() async throws {
    let delivery = TransactionDelivery()
    let probe = DeliveryProbe()
    let revision = TransactionRevision(id: 1, signedDate: Date())

    await #expect(throws: DeliveryError.self) {
        try await delivery.deliver(
            revision: revision,
            using: { throw DeliveryError.unavailable },
            finish: { probe.events.append("finished") }
        )
    }
    #expect(probe.events.isEmpty)

    try await delivery.deliver(
        revision: revision,
        using: { probe.events.append("delivered") },
        finish: { probe.events.append("finished") }
    )
    #expect(probe.events == ["delivered", "finished"])
}

@MainActor
@Test func overlappingDeliveryAttemptsShareTheSameWork() async throws {
    let delivery = TransactionDelivery()
    let probe = DeliveryProbe()
    let revision = TransactionRevision(id: 1, signedDate: Date())
    let firstAttempt = Task {
        try await delivery.deliver(
            revision: revision,
            using: {
                probe.events.append("delivered")
                await probe.pause()
            },
            finish: { probe.events.append("finished") }
        )
    }
    while probe.continuation == nil { await Task.yield() }

    var secondAttemptStarted = false
    let secondAttempt = Task {
        secondAttemptStarted = true
        try await delivery.deliver(
            revision: revision,
            using: { probe.events.append("duplicate") },
            finish: { probe.events.append("duplicate finish") }
        )
    }
    while !secondAttemptStarted { await Task.yield() }
    probe.resume()
    try await firstAttempt.value
    try await secondAttempt.value

    #expect(probe.events == ["delivered", "finished"])
}

@MainActor
@Test func revocationWaitsForAnEarlierDeliveryOfTheSameTransaction() async throws {
    let delivery = TransactionDelivery()
    let probe = DeliveryProbe()
    let signedDate = Date(timeIntervalSince1970: 1)
    let firstAttempt = Task {
        try await delivery.deliver(
            revision: TransactionRevision(id: 1, signedDate: signedDate),
            using: {
                probe.events.append("delivered")
                await probe.pause()
            },
            finish: { probe.events.append("finished purchase") }
        )
    }
    while probe.continuation == nil { await Task.yield() }

    var revocationStarted = false
    let revocationAttempt = Task {
        revocationStarted = true
        try await delivery.deliver(
            revision: TransactionRevision(id: 1, signedDate: signedDate, revocationDate: Date()),
            using: { probe.events.append("revoked") },
            finish: { probe.events.append("finished revocation") }
        )
    }
    while !revocationStarted { await Task.yield() }
    #expect(probe.events == ["delivered"])
    probe.resume()
    try await firstAttempt.value
    try await revocationAttempt.value

    #expect(probe.events == ["delivered", "finished purchase", "revoked", "finished revocation"])
}

@MainActor
@Test func cancelledDeliveryDoesNotFinishTheTransaction() async throws {
    let delivery = TransactionDelivery()
    let probe = DeliveryProbe()
    let revision = TransactionRevision(id: 1, signedDate: Date())
    let attempt = Task {
        try await delivery.deliver(
            revision: revision,
            using: { await probe.pause() },
            finish: { probe.events.append("finished") }
        )
    }
    while probe.continuation == nil { await Task.yield() }
    attempt.cancel()
    probe.resume()

    await #expect(throws: CancellationError.self) { try await attempt.value }
    #expect(probe.events.isEmpty)
}

@Test func stateBasedProductsFinishWithoutAHandler() {
    #expect(PurchaseManager.finishesWithoutHandler(.nonConsumable))
    #expect(PurchaseManager.finishesWithoutHandler(.autoRenewable))
}

@Test func deliveredProductsWaitForAHandler() {
    #expect(!PurchaseManager.finishesWithoutHandler(.consumable))
    #expect(!PurchaseManager.finishesWithoutHandler(.nonRenewable))
}
