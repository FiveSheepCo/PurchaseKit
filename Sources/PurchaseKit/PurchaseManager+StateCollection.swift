import Foundation
import StoreKit

extension PurchaseManager {

    /// Collect current access separately from historical transaction information.
    func collectProductStateSnapshot() async -> ProductStateSnapshot {
        let productIds = Set(self.registeredProducts.map(\.id)).union(self.productStates.keys)
        var snapshot = ProductStateSnapshot(productIds: productIds, consumableProductIds: self.consumableProductIds)

        // Keep known revocations and upgrades when StoreKit returns an older cached snapshot
        for transaction in self.transactionCache.values where transaction.revocationDate != nil || transaction.isUpgraded {
            snapshot.collect(transaction)
        }
        for result in self.pendingTransactions.values {
            self.collect(result, into: &snapshot)
        }
        for await result in Transaction.currentEntitlements {
            if let transaction = self.collect(result, into: &snapshot) {
                snapshot.currentEntitlementIds.insert(transaction.id)
            }
        }

        // Latest transactions also identify products that have expired or been revoked
        for productId in snapshot.productIds {
            guard let result = await Transaction.latest(for: productId) else { continue }
            self.collect(result, into: &snapshot)
        }
        return snapshot
    }

    @discardableResult
    func collect(
        _ result: VerificationResult<Transaction>,
        into snapshot: inout ProductStateSnapshot
    ) -> Transaction? {
        guard let transaction = self.resolveTransaction(for: result) else { return nil }
        if transaction.productType == .consumable {
            // Remember the type after finished consumables disappear from StoreKit history
            self.consumableProductIds.insert(transaction.productID)
        }
        return snapshot.collect(transaction)
    }
}
