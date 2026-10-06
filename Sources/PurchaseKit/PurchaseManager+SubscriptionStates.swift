import Foundation
import StoreKit

extension PurchaseManager {

    /// Retain the full status update, including changes that do not create a new transaction.
    func rememberSubscriptionStatus(_ status: StoreKit::Product.SubscriptionInfo.Status) {
        guard let resolvedStatus = self.resolveSubscriptionStatus(status, fromUpdate: true) else { return }
        self.pendingSubscriptionStatuses[resolvedStatus.transaction.originalID] = status
        self.pendingTransactions[resolvedStatus.transaction.id] = status.transaction
    }

    /// Query every subscription group to preserve independent purchased and shared access.
    func collectSubscriptionStates(into snapshot: inout ProductStateSnapshot) async -> [UInt64: Transaction] {
        var groupIds = Set(snapshot.transactions.values.compactMap(\.subscriptionGroupID))
        groupIds.formUnion(self.products.compactMap { $0.skProduct.subscription?.subscriptionGroupID })
        var statusesByOriginalId: [UInt64: ResolvedSubscriptionStatus] = [:]

        // Terminal updates still remove access when the next status query fails
        for status in self.subscriptionStatusCache.values where status.removesAccess {
            statusesByOriginalId[status.transaction.originalID] = status
        }
        for status in self.pendingSubscriptionStatuses.values {
            guard let resolvedStatus = self.resolveSubscriptionStatus(status) else { continue }
            statusesByOriginalId[resolvedStatus.transaction.originalID] = resolvedStatus
        }
        for groupId in groupIds {
            do {
                for status in try await StoreKit::Product.SubscriptionInfo.status(for: groupId) {
                    guard let resolvedStatus = self.resolveSubscriptionStatus(status) else { continue }
                    statusesByOriginalId[resolvedStatus.transaction.originalID] = resolvedStatus
                }
            } catch {
                self.logger.error("Failed to fetch subscription status for group '\(groupId)': \(error)")
            }
        }
        return self.appendSubscriptionStates(statusesByOriginalId.values, to: &snapshot)
    }

    /// Apply only statuses covering the newest known transaction period in their ownership chain.
    private func appendSubscriptionStates(
        _ statuses: Dictionary<UInt64, ResolvedSubscriptionStatus>.Values,
        to snapshot: inout ProductStateSnapshot
    ) -> [UInt64: Transaction] {
        for status in statuses {
            let transaction = status.isVerified
                ? self.resolveTransaction(for: .verified(status.transaction)) ?? status.transaction
                : status.transaction
            snapshot.collect(transaction)
        }
        let latestTransactions = snapshot.latestSubscriptionTransactions()
        var subscriptionTransactions: [UInt64: Transaction] = [:]
        for status in statuses {
            let transaction = snapshot.transactions[status.transaction.id] ?? status.transaction
            if let latestTransaction = latestTransactions[transaction.originalID],
               !status.version.covers(SubscriptionTransaction(latestTransaction)) {
                continue
            }
            subscriptionTransactions[transaction.originalID] = transaction
            snapshot.append(self.resolveProductState(for: status, transaction: transaction), for: transaction)
        }
        return subscriptionTransactions
    }

    private func resolveSubscriptionStatus(
        _ status: StoreKit::Product.SubscriptionInfo.Status,
        fromUpdate: Bool = false
    ) -> ResolvedSubscriptionStatus? {
        guard let transaction = self.resolveVerifiedValue(for: status.transaction),
              let renewalInfo = self.resolveVerifiedValue(for: status.renewalInfo) else { return nil }
        let isVerified: Bool
        if case .verified = status.transaction, case .verified = status.renewalInfo {
            isVerified = true
        } else {
            isVerified = false
        }
        let resolvedStatus = ResolvedSubscriptionStatus(
            transaction: transaction,
            state: status.state,
            gracePeriodExpirationDate: renewalInfo.gracePeriodExpirationDate,
            signedDate: renewalInfo.signedDate,
            isVerified: isVerified
        )
        guard isVerified else { return resolvedStatus }
        return self.subscriptionStatusCache.collect(resolvedStatus, version: resolvedStatus.version, fromUpdate: fromUpdate)
    }
}
