import Foundation
import StoreKit

/// The signed transaction version being delivered or reconciled.
struct TransactionRevision: Hashable {
    let id: Transaction.ID
    let signedDate: Date
    let revocationDate: Date?
    let isUpgraded: Bool

    init(_ transaction: Transaction) {
        self.init(
            id: transaction.id,
            signedDate: transaction.signedDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded
        )
    }

    init(id: Transaction.ID, signedDate: Date, revocationDate: Date? = nil, isUpgraded: Bool = false) {
        self.id = id
        self.signedDate = signedDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
    }
}

/// Serializes deliveries and finishes transactions only after the handler succeeds.
@MainActor
final class TransactionDelivery {
    private struct Attempt {
        let revision: TransactionRevision
        let task: Task<Void, Error>
    }

    private var attempts: [Transaction.ID: Attempt] = [:]

    func deliver(
        revision: TransactionRevision,
        using handler: (@MainActor @Sendable () async throws -> Void)?,
        finish: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        guard let handler else { return }
        try Task.checkCancellation()

        let previousAttempt = self.attempts[revision.id]
        if let previousAttempt, previousAttempt.revision == revision {
            // Startup and the updates listener may receive the same transaction together
            try await previousAttempt.task.value
            return
        }

        let task = Task {
            // A revocation must not race with delivery of the same transaction
            if let previousAttempt {
                _ = try? await previousAttempt.task.value
            }
            try Task.checkCancellation()
            try await handler()
            try Task.checkCancellation()
            await finish()
        }
        self.attempts[revision.id] = Attempt(revision: revision, task: task)
        defer {
            if self.attempts[revision.id]?.revision == revision {
                self.attempts[revision.id] = nil
            }
        }

        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
