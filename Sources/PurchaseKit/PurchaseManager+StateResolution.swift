import Foundation
import StoreKit

extension PurchaseManager {

    func resolveProductState(for transaction: Transaction) async -> ProductState {
        switch transaction.productType {
            case .nonRenewable:
                if let revocation = resolveRevocation(for: transaction) {
                    return .revoked(revocation)
                }
                return await resolveNonRenewingSubscriptionState(for: transaction)
            default:
                return ProductState.resolveIAPState(
                    for: transaction.productType,
                    revocation: resolveRevocation(for: transaction)
                )
        }
    }

    func resolveProductState(for status: ResolvedSubscriptionStatus, transaction: Transaction) -> ProductState {
        return ProductState.resolveSubscriptionState(
            for: status.state,
            expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: status.gracePeriodExpirationDate,
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
