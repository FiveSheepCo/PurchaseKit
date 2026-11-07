import Foundation
import StoreKit

/// Apps without entitlements set up the manager with `setup()`, which uses `Never`.
extension Never: Entitlement {}

extension PurchaseManager {

    /// Set up the manager with the app's products and entitlements, then call `start()`.
    ///
    /// ```swift
    /// let entitlements = PurchaseManager.shared.setup(entitlements: AppEntitlement.self)
    ///     .add(iap: "founders_pack", grants: .founder)
    ///     .add(subscription: "pro_monthly", grants: .pro)
    ///     .start()
    ///
    /// entitlements.isActive(.founder)
    /// ```
    public func setup<E: Entitlement>(entitlements: E.Type) -> Setup<E> {
        Setup(manager: self)
    }

    /// Set up the manager with the app's products, then call `start()`.
    public func setup() -> Setup<Never> {
        Setup(manager: self)
    }

    /// Register a product once, however many entitlements it grants.
    func registerProduct(_ id: String, kind: ProductKind) {
        guard !self.registeredProducts.contains(where: { $0.id == id }) else { return }
        self.registeredProducts.append(RegisteredProduct(id: id, kind: kind))
    }

    /// The products and policies of the manager, applied together when it starts.
    ///
    /// Set up the manager once, at launch. Each method returns an updated setup;
    /// nothing reaches the manager until `start()`.
    @MainActor
    public struct Setup<E: Entitlement> {
        private struct Registration {
            let id: String
            let kind: ProductKind
            let entitlements: [E]
        }

        private let manager: PurchaseManager
        private var registrations: [Registration] = []
        var config = PurchaseManagerConfiguration()

        init(manager: PurchaseManager) {
            self.manager = manager
        }

        /// Register an IAP that grants the given entitlements while it's active.
        ///
        /// Consumables never grant entitlements; deliver them with a transaction handler.
        public func add(iap id: String, grants entitlements: E...) -> Self {
            self.adding(id, kind: .iap, entitlements)
        }

        /// Register a subscription that grants the given entitlements while it's active.
        public func add(subscription id: String, grants entitlements: E...) -> Self {
            self.adding(id, kind: .subscription, entitlements)
        }

        /// Handle transactions before marking them as finished in StoreKit.
        ///
        /// Return only after delivering or reconciling the purchased content durably.
        /// Throw to leave the transaction unfinished; `refresh()` retries unfinished transactions.
        /// Without a handler, non-consumables and auto-renewable subscriptions are finished
        /// automatically, since their access follows from product states.
        /// Consumables and non-renewing subscriptions remain unfinished until a handler delivers them.
        ///
        /// Use the transaction's `id` to make delivery idempotent across retries and app launches.
        /// For consumables, persist the delivered `purchasedQuantity` with the transaction ID.
        /// Handle refunds and revocations without delivering the purchased content again.
        public func handleTransactions(
            using handler: @escaping @MainActor @Sendable (Transaction) async throws -> Void
        ) -> Self {
            var setup = self
            setup.config.transactionHandler = handler
            return setup
        }

        /// Allow unverified transactions and subscription renewal information to be handled.
        ///
        /// - Warning: This is highly discouraged and should never be done in production environments!
        public func allowUnverifiedTransactions(_ enabled: Bool = true) -> Self {
            var setup = self
            setup.config.allowUnverifiedTransactions = enabled
            return setup
        }

        /// Allow accessing products during billing retry.
        public func allowAccessDuringBillingRetry(_ enabled: Bool = true) -> Self {
            var setup = self
            setup.config.allowAccessDuringBillingRetry = enabled
            return setup
        }

        /// Resolve non-renewing subscription states using the app's entitlement policy.
        ///
        /// Use trusted server data to determine expiration independently of the device clock.
        /// Without a resolver, non-renewing subscriptions have an unknown state.
        /// The policy is rechecked every minute while the manager is running.
        public func resolveNonRenewingSubscriptions(
            using resolver: @escaping @MainActor @Sendable (Transaction) async throws -> ProductState
        ) -> Self {
            var setup = self
            setup.config.nonRenewingSubscriptionStateResolver = resolver
            return setup
        }

        /// Show the last known product states at launch until the first refresh completes.
        ///
        /// StoreKit needs a moment after launch to report entitlements; without this, paid
        /// content appears locked until it does. The stored states are only for display:
        /// every refresh replaces them with StoreKit's.
        public func cacheStates(in defaults: UserDefaults = .standard, key: String = "PurchaseKit.productStates") -> Self {
            var setup = self
            setup.config.stateCacheLocation = DefaultsLocation(defaults: defaults, key: key)
            return setup
        }

        /// Let the app force entitlements on or off with `setOverride(_:isActive:)`, to try paid
        /// features without buying them. Overrides are remembered in `defaults` between launches.
        ///
        /// - Warning: Allow this in debug builds only, or anyone could unlock everything:
        ///   ```swift
        ///   #if DEBUG
        ///   setup = setup.allowEntitlementOverrides()
        ///   #endif
        ///   ```
        public func allowEntitlementOverrides(
            in defaults: UserDefaults = .standard,
            key: String = "PurchaseKit.entitlementOverrides"
        ) -> Self {
            var setup = self
            setup.config.overrideLocation = DefaultsLocation(defaults: defaults, key: key)
            return setup
        }

        /// Apply the setup, start handling transactions, and load products and entitlements.
        ///
        /// - Returns: The manager seen through the app's entitlement enum.
        @discardableResult
        public func start() -> Entitlements<E> {
            self.apply()
            self.manager.start()
            return self.manager.entitlements(E.self)
        }

        /// Hand the products and policies to the manager without starting it.
        func apply() {
            guard !self.manager.isSetUp else {
                assertionFailure("PurchaseManager is already set up; set it up once, at launch")
                return
            }
            self.manager.isSetUp = true
            self.manager.config = self.config
            self.manager.loadEntitlementOverrides()
            for registration in self.registrations {
                self.manager.registerProduct(registration.id, kind: registration.kind)
                for entitlement in registration.entitlements {
                    self.manager.entitlementProductIds[AnyHashable(entitlement), default: []].insert(registration.id)
                }
            }
        }

        private func adding(_ id: String, kind: ProductKind, _ entitlements: [E]) -> Self {
            var setup = self
            setup.registrations.append(Registration(id: id, kind: kind, entitlements: entitlements))
            return setup
        }
    }
}
