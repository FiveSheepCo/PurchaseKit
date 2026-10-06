import Foundation
import StoreKit

extension PurchaseManager {

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

    func resolveProductState(
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

    func resolveRevocation(for transaction: Transaction) -> RevokedProductState? {
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
