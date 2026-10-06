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

        // Retain known revocations and upgrades even when StoreKit returns an older cached snapshot
        var transactions = self.transactionCache.values.filter {
            $0.revocationDate != nil || $0.isUpgraded
        }.reduce(into: [Transaction.ID: Transaction]()) { $0[$1.id] = $1 }

        @discardableResult
        func collect(_ result: VerificationResult<Transaction>) -> Transaction? {
            guard let transaction = resolveTransaction(for: result) else { return nil }
            if let existingTransaction = transactions[transaction.id],
               !TransactionRevision(transaction).supersedes(TransactionRevision(existingTransaction)) {
                return existingTransaction
            }
            transactions[transaction.id] = transaction
            return transaction
        }

        for result in self.pendingTransactions.values {
            collect(result)
        }

        // Current entitlements include every valid ownership source, including Family Sharing
        for await result in Transaction.currentEntitlements {
            collect(result)
        }

        // Latest transactions also identify products that have expired or been revoked
        var productIds = Set(self.registeredProducts.map(\.id))
        productIds.formUnion(self.productStates.keys)
        productIds.formUnion(transactions.values.map(\.productID))
        for productId in productIds {
            guard let result = await Transaction.latest(for: productId) else { continue }
            collect(result)
        }

        var subscriptionGroupIds = Set(transactions.values.compactMap(\.subscriptionGroupID))
        subscriptionGroupIds.formUnion(self.products.compactMap { $0.skProduct.subscription?.subscriptionGroupID })
        var subscriptionTransactions: [UInt64: Transaction] = [:]
        var candidates: [(transaction: Transaction, state: ProductState)] = []

        // Resolve all statuses in each group so one revoked ownership source cannot remove valid access
        for subscriptionGroupId in subscriptionGroupIds {
            do {
                let subscriptionStatuses = try await StoreKit::Product.SubscriptionInfo.status(for: subscriptionGroupId)
                for subscriptionStatus in subscriptionStatuses {
                    guard let transaction = collect(subscriptionStatus.transaction) else { continue }
                    subscriptionTransactions[transaction.originalID] = transaction
                    productIds.insert(transaction.productID)
                    let state = resolveProductState(for: subscriptionStatus, transaction: transaction)
                    candidates.append((transaction, state))
                }
            } catch {
                self.logger.error("Failed to fetch subscription status for group '\(subscriptionGroupId)': \(error)")
            }
        }

        for transaction in transactions.values {
            if transaction.productType == .autoRenewable {
                let subscriptionTransaction = subscriptionTransactions[transaction.originalID]
                let wasReplaced = subscriptionTransaction.map { $0.productID != transaction.productID } ?? false
                if let revocation = resolveRevocation(for: transaction) {
                    candidates.append((transaction, .revoked(revocation)))
                } else if transaction.isUpgraded || wasReplaced {
                    // A replacement subscription does not grant access to the previous product
                    let state = transaction.expirationDate.map {
                        ProductState.expired(ExpiredProductState(expirationDate: $0))
                    } ?? .unknown
                    candidates.append((transaction, state))
                } else if subscriptionTransaction == nil {
                    candidates.append((transaction, .unknown))
                }
            } else {
                let state = await resolveProductState(for: transaction)
                candidates.append((transaction, state))
            }
        }

        // Prefer current access; otherwise retain the most recent known inactive state
        candidates.sort { lhs, rhs in
            if lhs.transaction.purchaseDate != rhs.transaction.purchaseDate {
                return lhs.transaction.purchaseDate > rhs.transaction.purchaseDate
            }
            if lhs.transaction.signedDate != rhs.transaction.signedDate {
                return lhs.transaction.signedDate > rhs.transaction.signedDate
            }
            return lhs.transaction.id > rhs.transaction.id
        }
        let candidatesByProductId = Dictionary(grouping: candidates, by: { $0.transaction.productID })
        var resolvedProductStates: [Product.ID: ProductState] = [:]
        for productId in productIds {
            let states = candidatesByProductId[productId]?.map(\.state) ?? []
            resolvedProductStates[productId] = ProductState.preferredState(from: states)
        }

        applyProductStates(resolvedProductStates, refreshVersion: refreshVersion)
    }

    func applyProductStates(_ resolvedProductStates: [Product.ID: ProductState], refreshVersion: UInt64) {
        guard refreshVersion == self.stateRefreshVersion, !Task.isCancelled else { return }
        self.productStates = resolvedProductStates
        self.pendingTransactions.removeAll()
    }
}
