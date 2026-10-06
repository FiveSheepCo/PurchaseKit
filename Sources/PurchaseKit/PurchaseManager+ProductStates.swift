import Foundation
import StoreKit

extension PurchaseManager {

    func refreshProductStates(updatedTransaction: VerificationResult<Transaction>? = nil) async {
        // Prevent an older refresh from overwriting a newer entitlement snapshot
        self.stateRefreshVersion += 1
        let refreshVersion = self.stateRefreshVersion
        if let updatedTransaction {
            // Preserve the verification result so changing the policy cannot trust an old unverified update
            self.pendingTransactions[updatedTransaction.unsafePayloadValue.id] = updatedTransaction
        }

        var snapshot = await self.collectProductStateSnapshot()
        let subscriptionTransactions = await self.collectSubscriptionStates(into: &snapshot)
        await self.resolveTransactionStates(in: &snapshot, subscriptions: subscriptionTransactions)
        self.applyProductStates(snapshot.resolvedStates(), refreshVersion: refreshVersion)
    }

    /// Resolve transaction states after collecting every available ownership source.
    private func resolveTransactionStates(
        in snapshot: inout ProductStateSnapshot,
        subscriptions subscriptionTransactions: [UInt64: Transaction]
    ) async {
        for transaction in snapshot.transactions.values {
            if transaction.productType == .autoRenewable {
                let subscriptionTransaction = subscriptionTransactions[transaction.originalID]
                let wasReplaced = subscriptionTransaction.map { $0.productID != transaction.productID } ?? false
                let revocation = resolveRevocation(for: transaction)
                if revocation != nil || transaction.isUpgraded || wasReplaced || subscriptionTransaction == nil {
                    snapshot.append(
                        ProductState.resolveSubscriptionFallback(
                            hasCurrentEntitlement: snapshot.currentEntitlementIds.contains(transaction.id),
                            expirationDate: transaction.expirationDate,
                            revocation: revocation,
                            isUpgraded: transaction.isUpgraded || wasReplaced
                        ),
                        for: transaction
                    )
                }
            } else {
                let state = await resolveProductState(for: transaction)
                snapshot.append(state, for: transaction)
            }
        }
    }

    func applyProductStates(_ resolvedProductStates: [Product.ID: ProductState], refreshVersion: UInt64) {
        guard refreshVersion == self.stateRefreshVersion, !Task.isCancelled else { return }
        self.productStates = resolvedProductStates
        self.pendingTransactions.removeAll()
    }
}
