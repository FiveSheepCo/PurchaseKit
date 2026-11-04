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
        guard self.resolveTransaction(for: result) != nil else { return }

        await self.refreshProductStates(updatedTransaction: result)
        guard !Task.isCancelled,
              let transaction = self.resolveTransaction(for: result) else { return }

        let delivery = self.delivery(for: transaction)
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

    /// The app's delivery for a transaction, or `nil` to leave it unfinished.
    func delivery(for transaction: Transaction) -> (@MainActor @Sendable () async throws -> Void)? {
        if let handler = self.config.transactionHandler {
            return { try await handler(transaction) }
        }
        guard Self.finishesWithoutHandler(transaction.productType) else { return nil }
        return {}
    }

    /// Whether a product type's access follows entirely from product states.
    ///
    /// Consumables and non-renewing subscriptions need the app to record each delivery.
    nonisolated static func finishesWithoutHandler(_ productType: StoreKit::Product.ProductType) -> Bool {
        productType == .nonConsumable || productType == .autoRenewable
    }
}
