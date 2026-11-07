import Foundation

extension PurchaseManager {

    /// The override set for an entitlement: `true` grants it, `false` withholds it, `nil` follows its products.
    public func override(for entitlement: any Entitlement) -> Bool? {
        self.entitlementOverrides[Self.overrideKey(for: entitlement)]
    }

    /// Force an entitlement on or off regardless of its products, or pass `nil` to follow them again.
    ///
    /// For debugging and testing paid features without a purchase. Requires
    /// `allowEntitlementOverrides(in:key:)` at setup; without it, nothing is overridden.
    /// Product states are unaffected: only entitlements see overrides.
    public func setOverride(_ entitlement: any Entitlement, isActive: Bool?) {
        guard let location = self.config.overrideLocation else {
            assertionFailure("Allow entitlement overrides at setup with allowEntitlementOverrides()")
            return
        }
        let key = Self.overrideKey(for: entitlement)
        guard self.entitlementOverrides[key] != isActive else { return }
        self.entitlementOverrides[key] = isActive
        location.defaults.set(self.entitlementOverrides, forKey: location.key)

        // Stream consumers read entitlements after an update, so they learn about overrides too
        for continuation in self.stateContinuations.values {
            continuation.yield(self.productStates)
        }
    }

    func loadEntitlementOverrides() {
        guard let location = self.config.overrideLocation else { return }
        self.entitlementOverrides = location.defaults.dictionary(forKey: location.key) as? [String: Bool] ?? [:]
    }

    /// Entitlements are compared by type and value, and so are their stored overrides.
    static func overrideKey(for entitlement: any Entitlement) -> String {
        String(reflecting: entitlement)
    }
}

extension ProductState {

    /// An entitlement's state with its override applied.
    func overridden(by override: Bool?) -> ProductState {
        switch override {
            case true?: self.isActive ? self : .active(ActiveProductState(expirationDate: nil))
            case false?: .unknown
            case nil: self
        }
    }
}
