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
        // Transactions with a revocation date have been refunded or revoked
        if let revocationDate = transaction.revocationDate {
            let revokedProduct = RevokedProductState(
                revocationDate: revocationDate,
                revocationReason: transaction.revocationReason,
                revocationPercentage: transaction.revocationPercentage
            )
            return .revoked(revokedProduct)
        }
        
        // Transactions with an expiration date can be ongoing or expired subscriptions
        else if let expirationDate = transaction.expirationDate {
            
            let isExplicitlyExpired: Bool = await {
                
                // Get subscription status
                guard let subscriptionStatus = await transaction.subscriptionStatus else {
                    return false
                }
                
                // Renewal states that explicitly expire or revoke a product
                var explicitExpirationStates: Set<StoreKit::Product.SubscriptionInfo.RenewalState> = [
                    .expired, .revoked, .inBillingRetryPeriod
                ]
                
                // Exclude billing retry from expiration states if requested
                if self.config.allowAccessDuringBillingRetry {
                    explicitExpirationStates.remove(.inBillingRetryPeriod)
                }
                
                // Check whether the product is explicitly expired.
                // This excludes billing retry and billing grace periods on purpose.
                return explicitExpirationStates.contains(subscriptionStatus.state)
            }()
            
            // Check whether the transaction has expired
            if isExplicitlyExpired {
                let expiredProduct = ExpiredProductState(expirationDate: expirationDate)
                return .expired(expiredProduct)
            }
            
            // Expiration date is in the future, treat as active
            else {
                let activeProduct = ActiveProductState(expirationDate: expirationDate)
                return .active(activeProduct)
            }
        }
        
        // Transactions with no revocation or expiration date are considered active
        else {
            let activeProduct = ActiveProductState(expirationDate: nil)
            return .active(activeProduct)
        }
    }
}
