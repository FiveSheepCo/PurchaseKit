import Foundation
import StoreKit

extension PurchaseManager {
    
    func fetchProducts() async throws {
        var resolvedProducts: [Product] = []
        
        // Fetch registered products from StoreKit
        let registeredProductIds = self.registeredProducts.map(\.id)
        let skProducts = try await StoreKit.Product.products(for: registeredProductIds)
        
        for skProduct in skProducts {
            
            // Map StoreKit product to our product
            switch skProduct.type {
                case .autoRenewable, .nonRenewable:
                    let product = Product(skProduct: skProduct, kind: .subscription)
                    resolvedProducts.append(product)
                case .consumable, .nonConsumable:
                    let product = Product(skProduct: skProduct, kind: .iap)
                    resolvedProducts.append(product)
                default:
                    logger.error("Unsupported product type '\(skProduct.type.localizedDescription)' for product '\(skProduct.id)'")
                    continue
            }
        }

        self.products = resolvedProducts
    }
    
    func setupUpdateTask() {
        guard self.updateTask == nil else { return }
        
        self.updateTask = Task {
            
            // Handle transaction updates
            for await result in Transaction.updates {
                await handle(verificationResult: result)
            }
            
            // If this ever exits (which it shouldn't), simply restart the task
            await MainActor.run {
                self.updateTask = nil
                self.setupUpdateTask()
            }
        }
    }
    
    private func handle(verificationResult result: VerificationResult<Transaction>) async {
        switch result {
            case .unverified(let transaction, let verificationError):
                self.logger.error("Verification error for transaction with ID '\(transaction.id)': \(verificationError)")
                if self.config.allowUnverifiedTransactions {
                    self.logger.warning("Accepted UNVERIFIED transaction with ID '\(transaction.id)' for product '\(transaction.productID)'")
                    await self.handle(updatedTransaction: transaction)
                } else {
                    self.logger.warning("Rejected UNVERIFIED transaction with ID '\(transaction.id)' for product '\(transaction.productID)'")
                }
            case .verified(let transaction):
                self.logger.info("Accepted verified transaction with ID '\(transaction.id)' for product '\(transaction.productID)'")
                await self.handle(updatedTransaction: transaction)
        }
    }
    
    private func handle(updatedTransaction transaction: Transaction) async {
        
        // Resolve and update product state
        let productState = await self.resolveProductState(for: transaction)
        self.productStates[transaction.productID] = productState
        
        // Mark the transaction as finished
        await transaction.finish()
    }
    
    private func resolveProductState(for transaction: Transaction) async -> ProductState {
        // Transactions with a revocation date have been refunded or revoked.
        if let revocation = resolveRevocation(for: transaction) {
            return .revoked(revocation)
        }

        // Auto-renewable subscriptions use the latest verified subscription status.
        if transaction.productType == .autoRenewable {
            guard let subscriptionStatus = await transaction.subscriptionStatus else {
                return .unknown
            }
            return resolveProductState(for: subscriptionStatus)
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

    func resolveProductState(for subscriptionStatus: StoreKit::Product.SubscriptionInfo.Status) -> ProductState {
        // Status may contain a newer transaction than the incoming update.
        guard let transaction = resolveVerifiedValue(for: subscriptionStatus.transaction),
              let renewalInfo = resolveVerifiedValue(for: subscriptionStatus.renewalInfo) else {
            return .unknown
        }

        return ProductState.resolveSubscriptionState(
            for: subscriptionStatus.state,
            expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: renewalInfo.gracePeriodExpirationDate,
            revocation: resolveRevocation(for: transaction),
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
