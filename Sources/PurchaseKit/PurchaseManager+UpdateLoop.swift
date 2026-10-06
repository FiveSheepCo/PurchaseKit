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

        self.updateTask = Task { [weak self] in
            // Handle transaction updates
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                await self.handle(verificationResult: result)
            }

            // Restart only if StoreKit ends the sequence without cancellation
            guard !Task.isCancelled else { return }
            self?.updateTask = nil
            self?.setupUpdateTask()
        }
    }

    func setupSubscriptionUpdateTask() {
        guard self.subscriptionUpdateTask == nil else { return }

        self.subscriptionUpdateTask = Task { [weak self] in
            // Status changes include expiration and the end of a grace period
            for await subscriptionStatus in StoreKit::Product.SubscriptionInfo.Status.updates {
                guard !Task.isCancelled, let self else { return }
                let transaction = self.resolveVerifiedValue(for: subscriptionStatus.transaction)
                await self.refreshProductStates(updatedTransaction: transaction)
            }

            // Restart only if StoreKit ends the sequence without cancellation
            guard !Task.isCancelled else { return }
            self?.subscriptionUpdateTask = nil
            self?.setupSubscriptionUpdateTask()
        }
    }

    func setupNonRenewingSubscriptionUpdateTask() {
        guard self.nonRenewingSubscriptionUpdateTask == nil,
              self.config.nonRenewingSubscriptionStateResolver != nil else { return }

        self.nonRenewingSubscriptionUpdateTask = Task { [weak self] in
            // Non-renewing expiration is managed by the app, so StoreKit does not emit a status change
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                await self.refreshProductStates()
            }
        }
    }

    func handle(verificationResult result: VerificationResult<Transaction>) async {
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
        
        // Recompute access across all ownership sources before updating product state
        await self.refreshProductStates(updatedTransaction: transaction)
        guard !Task.isCancelled else { return }
        
        // Mark the transaction as finished
        await transaction.finish()
    }
    
}
