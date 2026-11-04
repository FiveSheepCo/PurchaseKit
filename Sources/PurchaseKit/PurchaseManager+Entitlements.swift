import Foundation

extension PurchaseManager {

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
