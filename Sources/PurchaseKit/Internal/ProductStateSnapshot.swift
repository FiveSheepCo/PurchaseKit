import Foundation
import StoreKit

/// The transactions, ownership sources, and state candidates collected during one refresh.
struct ProductStateSnapshot {
    private struct Candidate {
        let transaction: Transaction
        let state: ProductState
    }

    private(set) var transactions: [Transaction.ID: Transaction] = [:]
    var currentEntitlementIds: Set<Transaction.ID> = []
    private(set) var productIds: Set<String>
    private var consumableProductIds: Set<String>
    private var candidates: [Candidate] = []

    init(productIds: Set<String>, consumableProductIds: Set<String> = []) {
        self.productIds = productIds
        self.consumableProductIds = consumableProductIds
    }

    @discardableResult
    mutating func collect(_ transaction: Transaction) -> Transaction {
        self.productIds.insert(transaction.productID)
        if transaction.productType == .consumable {
            // Consumables are delivered by transaction and never establish permanent product access
            self.consumableProductIds.insert(transaction.productID)
            return transaction
        }
        if let existingTransaction = self.transactions[transaction.id],
           !TransactionRevision(transaction).supersedes(TransactionRevision(existingTransaction)) {
            return existingTransaction
        }
        self.transactions[transaction.id] = transaction
        return transaction
    }

    mutating func append(_ state: ProductState, for transaction: Transaction) {
        self.candidates.append(Candidate(transaction: transaction, state: state))
    }

    /// Find the most recent period for each independently purchased or shared subscription.
    func latestSubscriptionTransactions() -> [UInt64: Transaction] {
        self.transactions.values.filter { $0.productType == .autoRenewable }.reduce(into: [:]) { latest, transaction in
            if let previous = latest[transaction.originalID],
               !SubscriptionTransaction(transaction).covers(SubscriptionTransaction(previous)) {
                return
            }
            latest[transaction.originalID] = transaction
        }
    }

    func resolvedStates() -> [Product.ID: ProductState] {
        // Prefer current access; otherwise retain the most recent known inactive state
        let sortedCandidates = self.candidates.sorted { lhs, rhs in
            if lhs.transaction.purchaseDate != rhs.transaction.purchaseDate {
                return lhs.transaction.purchaseDate > rhs.transaction.purchaseDate
            }
            if lhs.transaction.signedDate != rhs.transaction.signedDate {
                return lhs.transaction.signedDate > rhs.transaction.signedDate
            }
            return lhs.transaction.id > rhs.transaction.id
        }
        let candidatesByProductId = Dictionary(grouping: sortedCandidates, by: { $0.transaction.productID })
        return self.productIds.subtracting(self.consumableProductIds).reduce(into: [:]) { states, productId in
            let candidates = candidatesByProductId[productId]?.map(\.state) ?? []
            states[productId] = ProductState.preferredState(from: candidates)
        }
    }
}
