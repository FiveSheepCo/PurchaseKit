import Foundation
import StoreKit

extension PurchaseManager {

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

    func resolveTransaction(for result: VerificationResult<Transaction>) -> Transaction? {
        guard let transaction = resolveVerifiedValue(for: result) else { return nil }
        guard case .verified = result else { return transaction }

        // Unverified information must never replace the verified transaction cache
        return self.transactionCache.collect(transaction, revision: TransactionRevision(transaction))
    }
}
