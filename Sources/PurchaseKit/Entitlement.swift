import Foundation

/// Access that one or more products grant, such as "Pro" sold monthly, yearly, and for life.
///
/// Define an app's entitlements as an enum, so they can't be mistyped:
///
/// ```swift
/// enum AppEntitlement: Entitlement {
///     case pro
/// }
///
/// let entitlements = PurchaseManager.shared.setup(entitlements: AppEntitlement.self)
///     .add(subscription: "pro_monthly", grants: .pro)
///     .add(iap: "pro_lifetime", grants: .pro)
///     .start()
///
/// entitlements.isActive(.pro)
/// ```
///
/// Entitlements are compared by type and value, so two enums never share an entitlement.
/// Their states derive from product states and are never stored.
public protocol Entitlement: Hashable, Sendable {}
