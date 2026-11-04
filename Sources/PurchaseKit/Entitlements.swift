import Foundation

/// The shared manager seen through one app's entitlement enum.
///
/// Its methods take the enum itself, so cases can be written as `.founder`
/// and entitlements of another type don't compile.
@MainActor
public struct Entitlements<E: Entitlement>: Sendable {
    let manager: PurchaseManager

    /// The access state of an entitlement, combined from every product that grants it.
    public func state(of entitlement: E) -> ProductState {
        self.manager.state(of: entitlement as any Entitlement)
    }

    /// Whether any product granting the entitlement is currently active.
    public func isActive(_ entitlement: E) -> Bool {
        self.manager.isActive(entitlement as any Entitlement)
    }

    /// The fetched products that grant the entitlement, for offering it in a store.
    public func products(granting entitlement: E) -> [Product] {
        self.manager.products(granting: entitlement as any Entitlement)
    }
}

extension PurchaseManager {

    /// A view of this manager that takes the app's entitlement enum directly.
    ///
    /// ```swift
    /// let entitlements = PurchaseManager.shared.entitlements(AppEntitlement.self)
    /// entitlements.isActive(.founder)
    /// ```
    public func entitlements<E: Entitlement>(_ type: E.Type) -> Entitlements<E> {
        Entitlements(manager: self)
    }
}
