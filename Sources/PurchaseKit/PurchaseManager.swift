import Foundation
import StoreKit
import OSLog

public struct PurchaseManagerConfiguration {
    var allowUnverifiedTransactions: Bool = false
    var allowAccessDuringBillingRetry: Bool = false
    var nonRenewingSubscriptionStateResolver: (@MainActor @Sendable (Transaction) async throws -> ProductState)?
}

@MainActor
public class PurchaseManager {
    public static let shared = PurchaseManager()
    
    let logger = Logger(subsystem: "PurchaseKit", category: "PurchaseManager")
    
    /// The task handling incoming transaction updates.
    var updateTask: Task<Void, Never>?

    /// The task handling subscription status changes.
    var subscriptionUpdateTask: Task<Void, Never>?

    /// The task periodically rechecking the app's non-renewing subscription policy.
    var nonRenewingSubscriptionUpdateTask: Task<Void, Never>?

    /// The task loading products and existing entitlements when the manager starts.
    var startupTask: Task<Void, Never>?

    /// The version of the latest product state refresh.
    var stateRefreshVersion: UInt64 = 0

    /// Transaction updates retained until the latest entitlement refresh completes.
    var pendingTransactions: [Transaction.ID: Transaction] = [:]
    
    /// Products that have been registered by the user and need to be fetched.
    var registeredProducts: [RegisteredProduct] = []
    
    /// Fully resolved and purchase-ready products.
    var products: [Product] = []
    
    /// The current state of each resolved product.
    var productStates: [Product.ID: ProductState] = [:]
    
    /// The purchase manager configuration.
    var config = PurchaseManagerConfiguration()
    
    public init() {}

    deinit {
        self.startupTask?.cancel()
        self.updateTask?.cancel()
        self.subscriptionUpdateTask?.cancel()
        self.nonRenewingSubscriptionUpdateTask?.cancel()
    }
    
    public func start() {
        setupUpdateTask()
        setupSubscriptionUpdateTask()
        setupNonRenewingSubscriptionUpdateTask()

        guard self.startupTask == nil else { return }
        self.startupTask = Task { [weak self] in
            guard let self else { return }
            defer { self.startupTask = nil }

            await self.refresh()

            // Process unfinished transactions even if the manager starts after app launch
            for await result in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                await self.handle(verificationResult: result)
            }
        }
    }

    /// Fetch registered products and refresh the customer's current entitlements.
    ///
    /// Call this when the app returns to the foreground or its entitlement policy changes.
    public func refresh() async {
        do {
            try await self.fetchProducts()
        } catch {
            self.logger.error("Failed to fetch products: \(error)")
        }
        await self.refreshProductStates()
    }
}
