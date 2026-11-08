# Changelog

All notable changes to PurchaseKit are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and PurchaseKit follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0.0, a minor release may change the API.

## [Unreleased]

The first public version.

### Added

- `PurchaseManager.shared`, set up once at launch with `setup()` or `setup(entitlements:)`, then `start()`.
- Register products with `add(iap:grants:)` and `add(subscription:grants:)`, each granting any number of app-defined entitlements.
- `Entitlement` protocol and the typed `entitlements(_:)` view, so entitlement cases are checked by the compiler.
- Observable product and entitlement states: `.active`, `.expired`, `.revoked`, and `.unknown`.
- `stateUpdates`, an async stream of state changes for code outside SwiftUI views.
- `purchase(_:)`, `process(_:)` for SwiftUI's `purchase` action, and `restore()`, reporting a `PurchaseOutcome`.
- `productsStatus`, telling a store whether products are loading, loaded, or failed to load.
- Transactions are finished only after the app's `handleTransactions(using:)` handler delivers them; failed deliveries are retried on the next refresh or launch.
- Subscription states from StoreKit's signed status rather than the device clock, including grace period and billing retry (`allowAccessDuringBillingRetry()`).
- Refunds, revocations, upgrades, and Family Sharing are tracked across refreshes, even when StoreKit returns an older snapshot.
- `resolveNonRenewingSubscriptions(using:)` to decide non-renewing subscription access from the app's own trusted data.
- `cacheStates(in:key:)` to show the last known states at launch.
- Automatic refresh when the app returns to the foreground, turned off with `refreshOnForeground(false)`.
- `allowEntitlementOverrides(in:key:)` and `setOverride(_:isActive:)` to force entitlements on or off in debug builds.
- `allowUnverifiedTransactions()` for debugging only.

[Unreleased]: https://github.com/FiveSheepCo/PurchaseKit/commits/main
