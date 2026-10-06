import Foundation
import StoreKit

extension PurchaseManager {

    /// Process a purchase result using the configured transaction handler.
    ///
    /// Pass successful purchases made in this app here, since StoreKit returns them
    /// through the purchase result instead of the transaction updates sequence.
    /// Delivery failures are logged and leave the transaction unfinished for a later retry.
    public func process(_ result: VerificationResult<Transaction>) async {
        await self.handle(verificationResult: result)
    }

    func retryUnfinishedTransactions() async {
        // StoreKit retains failed deliveries until the app successfully finishes them
        for await result in Transaction.unfinished {
            guard !Task.isCancelled else { return }
            await self.handle(verificationResult: result)
        }
    }

    func handle(verificationResult result: VerificationResult<Transaction>) async {
        guard let transaction = resolveVerifiedValue(for: result) else { return }

        await self.refreshProductStates(updatedTransaction: result)
        guard !Task.isCancelled else { return }

        let delivery = self.config.transactionHandler.map { handler in
            { @MainActor @Sendable in try await handler(transaction) }
        }
        do {
            try await self.transactionDelivery.deliver(
                revision: TransactionRevision(transaction),
                using: delivery,
                finish: { await transaction.finish() }
            )
        } catch {
            self.logger.error("Failed to handle transaction '\(transaction.id)': \(error)")
        }
    }
}
