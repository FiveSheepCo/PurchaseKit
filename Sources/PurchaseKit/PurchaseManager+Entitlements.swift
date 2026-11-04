import Foundation

extension PurchaseManager {

    /// Register an IAP that grants the given entitlements while it's active.
    ///
    /// Consumables never grant entitlements; deliver them with a transaction handler.
    @discardableResult
    public func add(iap id: String, grants entitlements: any Entitlement...) -> Self {
        self.register(id, kind: .iap, granting: entitlements)
    }

    /// Register a subscription that grants the given entitlements while it's active.
    @discardableResult
    public func add(subscription id: String, grants entitlements: any Entitlement...) -> Self {
        self.register(id, kind: .subscription, granting: entitlements)
    }

    /// The access state of an entitlement, combined from every product that grants it.
    public func state(of entitlement: any Entitlement) -> ProductState {
        let productIds = self.entitlementProductIds[AnyHashable(entitlement)] ?? []
        return ProductState.combinedState(from: productIds.map(self.state(for:)))
    }

    /// Whether any product granting the entitlement is currently active.
    public func isActive(_ entitlement: any Entitlement) -> Bool {
        self.state(of: entitlement).isActive
    }

    /// The fetched products that grant the entitlement, for offering it in a store.
    public func products(granting entitlement: any Entitlement) -> [Product] {
        let productIds = self.entitlementProductIds[AnyHashable(entitlement)] ?? []
        return self.products.filter { productIds.contains($0.id) }
    }

    private func register(_ id: String, kind: ProductKind, granting entitlements: [any Entitlement]) -> Self {
        self.registerProduct(id, kind: kind)
        for entitlement in entitlements {
            self.entitlementProductIds[AnyHashable(entitlement), default: []].insert(id)
        }
        return self
    }

    /// Register a product once, however many entitlements it grants.
    func registerProduct(_ id: String, kind: ProductKind) {
        guard !self.registeredProducts.contains(where: { $0.id == id }) else { return }
        self.registeredProducts.append(RegisteredProduct(id: id, kind: kind))
    }
}

extension ProductState {

    /// Combine the states of every product granting the same entitlement.
    ///
    /// The result doesn't depend on the order of the states.
    static func combinedState(from states: [ProductState]) -> ProductState {
        // Permanent access outlasts any expiring access, and later expirations outlast earlier ones
        let activeStates = states.compactMap { state -> ActiveProductState? in
            guard case .active(let active) = state else { return nil }
            return active
        }
        if !activeStates.isEmpty {
            let longest = activeStates.max { lhs, rhs in
                guard let lhsDate = lhs.expirationDate else { return false }
                guard let rhsDate = rhs.expirationDate else { return true }
                return lhsDate < rhsDate
            }
            return longest.map(ProductState.active) ?? .unknown
        }

        // Without access, report what ended most recently
        let endedStates = states.filter { $0.isExpired || $0.isRevoked }
        let latest = endedStates.max { lhs, rhs in
            if lhs.endDate != rhs.endDate {
                return lhs.endDate < rhs.endDate
            }
            // A revocation explains lost access better than an expiration on the same date
            return lhs.isRevoked == false && rhs.isRevoked
        }
        return latest ?? .unknown
    }

    private var endDate: Date {
        switch self {
            case .expired(let expired): expired.expirationDate
            case .revoked(let revoked): revoked.revocationDate ?? .distantPast
            case .active, .unknown: .distantPast
        }
    }
}
