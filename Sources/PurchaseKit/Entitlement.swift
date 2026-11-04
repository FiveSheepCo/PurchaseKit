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
/// PurchaseManager.shared
///     .add(subscription: "pro_monthly", grants: AppEntitlement.pro)
///     .add(iap: "pro_lifetime", grants: AppEntitlement.pro)
///
/// PurchaseManager.shared.isActive(AppEntitlement.pro)
/// ```
///
/// Entitlements are compared by type and value, so two enums never share an entitlement.
/// Their states derive from product states and are never stored.
public protocol Entitlement: Hashable, Sendable {}
