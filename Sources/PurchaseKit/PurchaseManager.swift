import Foundation
import StoreKit
import OSLog
import Observation

struct PurchaseManagerConfiguration {
    var allowUnverifiedTransactions: Bool = false
    var allowAccessDuringBillingRetry: Bool = false
    var nonRenewingSubscriptionStateResolver: (@MainActor @Sendable (Transaction) async throws -> ProductState)?
    var transactionHandler: (@MainActor @Sendable (Transaction) async throws -> Void)?
    var stateCacheLocation: ProductStateCacheLocation?
}

@MainActor
@Observable
public class PurchaseManager {
    /// The app's purchase manager.
    ///
    /// StoreKit delivers transactions to the whole app, so a second manager would
    /// listen for and try to finish the same transactions.
    public static let shared = PurchaseManager()
    
    let logger = Logger(subsystem: "PurchaseKit", category: "PurchaseManager")
    
    /// The task handling incoming transaction updates.
    @ObservationIgnored
    var updateTask: Task<Void, Never>?

    /// The task handling subscription status changes.
    @ObservationIgnored
    var subscriptionUpdateTask: Task<Void, Never>?

    /// The task periodically rechecking the app's non-renewing subscription policy.
    @ObservationIgnored
    var nonRenewingSubscriptionUpdateTask: Task<Void, Never>?

    /// The task loading products and existing entitlements when the manager starts.
    @ObservationIgnored
    var startupTask: Task<Void, Never>?

    /// The coordinator serializing delivery attempts for each transaction.
    let transactionDelivery = TransactionDelivery()

    /// The version of the latest product state refresh.
    @ObservationIgnored
    var stateRefreshVersion: UInt64 = 0

    /// Transaction updates retained until the latest entitlement refresh completes.
    @ObservationIgnored
    var pendingTransactions: [Transaction.ID: VerificationResult<Transaction>] = [:]

    /// The newest verified transaction information observed during this session.
    @ObservationIgnored
    var transactionCache = TransactionCache<Transaction>()
    
    /// Status updates retained until the latest entitlement refresh completes.
    @ObservationIgnored
    var pendingSubscriptionStatuses: [UInt64: StoreKit::Product.SubscriptionInfo.Status] = [:]

    /// The newest verified renewal information observed for each ownership source.
    @ObservationIgnored
    var subscriptionStatusCache = SubscriptionStatusCache<ResolvedSubscriptionStatus>()

    /// Products that have been registered by the user and need to be fetched.
    @ObservationIgnored
    var registeredProducts: [RegisteredProduct] = []
    
    /// Fully resolved and purchase-ready products.
    public internal(set) var products: [Product] = []

    /// Whether the registered products are being fetched, were fetched, or couldn't be.
    public internal(set) var productsStatus: ProductsStatus = .notLoaded

    /// The products granting each entitlement, keyed by the entitlement's type and value.
    @ObservationIgnored
    var entitlementProductIds: [AnyHashable: Set<Product.ID>] = [:]

    /// Product identifiers known to represent consumable quantities rather than permanent access.
    @ObservationIgnored
    var consumableProductIds: Set<String> = []
    
    /// The current access state of each product, excluding consumable quantities.
    public internal(set) var productStates: [Product.ID: ProductState] = [:]
    
    /// Streams receiving product state changes.
    @ObservationIgnored
    var stateContinuations: [UUID: AsyncStream<[Product.ID: ProductState]>.Continuation] = [:]

    /// Whether a setup has been applied; the manager is set up once.
    @ObservationIgnored
    var isSetUp = false

    /// The purchase manager configuration.
    @ObservationIgnored
    var config = PurchaseManagerConfiguration()
    
    init() {}

    deinit {
        self.startupTask?.cancel()
        self.updateTask?.cancel()
        self.subscriptionUpdateTask?.cancel()
        self.nonRenewingSubscriptionUpdateTask?.cancel()
    }
    
    func start() {
        loadCachedStates()
        setupUpdateTask()
        setupSubscriptionUpdateTask()
        setupNonRenewingSubscriptionUpdateTask()

        guard self.startupTask == nil else { return }
        self.startupTask = Task { [weak self] in
            guard let self else { return }
            defer { self.startupTask = nil }

            await self.refresh()
        }
    }

    /// Fetch products, refresh current entitlements, and retry unfinished transactions.
    ///
    /// Call this when the app returns to the foreground or its entitlement policy changes.
    public func refresh() async {
        do {
            try await self.fetchProducts()
        } catch {
            self.logger.error("Failed to fetch products: \(error)")
        }
        await self.refreshProductStates()
        await self.retryUnfinishedTransactions()
    }
}
