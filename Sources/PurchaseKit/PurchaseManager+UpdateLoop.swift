import Foundation
import StoreKit

extension PurchaseManager {
    
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
                await self.refreshProductStates(updatedSubscriptionStatus: subscriptionStatus)
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
}
