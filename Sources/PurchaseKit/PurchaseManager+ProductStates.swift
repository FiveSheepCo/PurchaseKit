import Foundation
import StoreKit

extension PurchaseManager {

    func refreshProductStates(updatedTransaction: Transaction? = nil) async {
        // Prevent an older refresh from overwriting a newer entitlement snapshot
        self.stateRefreshVersion += 1
        let refreshVersion = self.stateRefreshVersion
        var transactions = self.pendingTransactions

        // The same transaction can be returned with newer revocation information
        func collect(_ transaction: Transaction) {
            if let existingTransaction = transactions[transaction.id],
               existingTransaction.signedDate >= transaction.signedDate {
                if existingTransaction.signedDate > transaction.signedDate || existingTransaction.revocationDate != nil {
                    return
                }
            }
            transactions[transaction.id] = transaction
        }

        if let updatedTransaction {
            collect(updatedTransaction)
            self.pendingTransactions = transactions
        }

        // Current entitlements include every valid ownership source, including Family Sharing
        for await result in Transaction.currentEntitlements {
            guard let transaction = resolveVerifiedValue(for: result) else { continue }
            collect(transaction)
        }

        // Latest transactions also identify products that have expired or been revoked
        var productIds = Set(self.registeredProducts.map(\.id))
        productIds.formUnion(self.productStates.keys)
        productIds.formUnion(transactions.values.map(\.productID))
        for productId in productIds {
            guard let result = await Transaction.latest(for: productId),
                  let transaction = resolveVerifiedValue(for: result) else { continue }
            collect(transaction)
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
                    guard let statusTransaction = resolveVerifiedValue(for: subscriptionStatus.transaction) else { continue }
                    collect(statusTransaction)
                    // A transaction update may contain newer revocation information than cached status
                    let transaction = transactions[statusTransaction.id] ?? statusTransaction
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

    func resolveProductState(for transaction: Transaction) async -> ProductState {
        // Transactions with a revocation date have been refunded or revoked
        if let revocation = resolveRevocation(for: transaction) {
            return .revoked(revocation)
        }

        switch transaction.productType {
            case .nonRenewable:
                return await resolveNonRenewingSubscriptionState(for: transaction)
            case .nonConsumable, .consumable:
                return .active(ActiveProductState(expirationDate: nil))
            default:
                return .unknown
        }
    }

    private func resolveProductState(
        for subscriptionStatus: StoreKit::Product.SubscriptionInfo.Status,
        transaction: Transaction
    ) -> ProductState {
        guard let renewalInfo = resolveVerifiedValue(for: subscriptionStatus.renewalInfo) else {
            return .unknown
        }

        return ProductState.resolveSubscriptionState(
            for: subscriptionStatus.state,
            expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: renewalInfo.gracePeriodExpirationDate,
            revocation: resolveRevocation(for: transaction),
            isUpgraded: transaction.isUpgraded,
            allowAccessDuringBillingRetry: self.config.allowAccessDuringBillingRetry
        )
    }

    func resolveVerifiedValue<Value>(for result: VerificationResult<Value>) -> Value? {
        switch result {
            case .verified(let value):
                return value
            case .unverified(let value, let verificationError):
                self.logger.error("StoreKit verification error: \(verificationError)")
                guard self.config.allowUnverifiedTransactions else { return nil }
                self.logger.warning("Accepted UNVERIFIED StoreKit information")
                return value
        }
    }

    private func resolveRevocation(for transaction: Transaction) -> RevokedProductState? {
        guard let revocationDate = transaction.revocationDate else { return nil }
        return RevokedProductState(
            revocationDate: revocationDate,
            revocationReason: transaction.revocationReason,
            revocationPercentage: transaction.revocationPercentage
        )
    }

    private func resolveNonRenewingSubscriptionState(for transaction: Transaction) async -> ProductState {
        guard let resolver = self.config.nonRenewingSubscriptionStateResolver else {
            return .unknown
        }

        do {
            return try await resolver(transaction)
        } catch {
            self.logger.error("Failed to resolve non-renewing subscription '\(transaction.productID)': \(error)")
            return .unknown
        }
    }
}
