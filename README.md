# PurchaseKit

PurchaseKit is a small StoreKit 2 layer that answers one question for your app: **what does this customer have access to right now?**

You describe your products and what they unlock. PurchaseKit loads them, listens for transactions, and keeps an up-to-date, observable state for every product and entitlement. It handles the parts of StoreKit that are easy to get wrong:

- **Verification.** Unverified transactions grant nothing (unless you opt in for debugging).
- **Refunds and revocations.** A refunded purchase stops granting access, and stays refunded even if StoreKit later returns an older snapshot.
- **Family Sharing and upgrades.** Shared and purchased access are tracked separately, and an upgraded subscription stops granting the old product.
- **Subscription states without the device clock.** Active, grace period, billing retry, and expiration come from StoreKit's signed status, so changing the date on the device changes nothing.
- **Reliable delivery.** A transaction is finished only after your app has delivered it. Failed deliveries are retried on the next refresh or launch.

> PurchaseKit is in active development. The API may still change before a tagged release.

## Requirements

- iOS 17 or macOS 14
- Swift 6.4 tools

## Installation

Add the package in Xcode (File → Add Package Dependencies) or in `Package.swift`:

```swift
.package(url: "https://github.com/FiveSheepCo/PurchaseKit.git", branch: "main")
```

## Quick start

### 1. Define what your products unlock

Entitlements are the things you sell, independent of how they're sold. Define them as an enum, so they can't be mistyped:

```swift
import PurchaseKit

enum AppEntitlement: Entitlement {
    case pro
    case founder
}
```

### 2. Set up the manager at launch

Register each product once, with the entitlements it grants, and start the manager. Several products can grant the same entitlement, such as a monthly and a yearly subscription.

```swift
@main
struct MyApp: App {
    init() {
        PurchaseManager.shared.setup(entitlements: AppEntitlement.self)
            .add(subscription: "pro_monthly", grants: .pro)
            .add(subscription: "pro_yearly", grants: .pro)
            .add(iap: "founders_pack", grants: .founder)
            .cacheStates()
            .start()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`start()` loads your products and the customer's current entitlements and starts listening for transactions. It refreshes again whenever the app comes back to the foreground, to catch up on what changed while it was away (turn that off with `refreshOnForeground(false)`). Set up the manager once; there is only one, `PurchaseManager.shared`, because StoreKit delivers transactions to the whole app.

`cacheStates()` is optional: it shows the last known states while StoreKit reports entitlements after launch, so paid content doesn't flash as locked.

An app without entitlements calls `setup()` instead and checks products directly:

```swift
PurchaseManager.shared.setup()
    .add(iap: "unlock")
    .start()

PurchaseManager.shared.isActive("unlock")
```

### 3. Check access

`entitlements(_:)` gives you a view that takes your enum directly. The manager is `@Observable`, so SwiftUI views update as soon as access changes, whether from a purchase, a refund, Family Sharing, or another device.

```swift
struct ContentView: View {
    private let entitlements = PurchaseManager.shared.entitlements(AppEntitlement.self)

    var body: some View {
        if entitlements.isActive(.pro) {
            ProFeatures()
        } else {
            Paywall()
        }
    }
}
```

`start()` also returns this view, if you'd rather keep it from the setup.

### 4. Sell products

In SwiftUI, buy with the `purchase` environment action, which shows the confirmation in the right window, and hand the result to PurchaseKit:

```swift
struct Paywall: View {
    @Environment(\.purchase) private var purchase
    private let entitlements = PurchaseManager.shared.entitlements(AppEntitlement.self)

    var body: some View {
        ForEach(entitlements.products(granting: .pro)) { product in
            Button("\(product.skProduct.displayName): \(product.skProduct.displayPrice)") {
                Task {
                    do {
                        let result = try await purchase(product.skProduct)
                        switch await PurchaseManager.shared.process(result) {
                            case .purchased: break  // access updates by itself
                            case .pending: break    // waiting for approval, such as Ask to Buy
                            case .cancelled: break
                            case .unverified: break // StoreKit couldn't verify it; nothing is granted
                        }
                    } catch {
                        // The purchase couldn't start, for example without a network connection
                    }
                }
            }
        }
    }
}
```

Outside SwiftUI, `try await PurchaseManager.shared.purchase(product)` does both steps.

Until the products arrive, `productsStatus` tells a store whether they're still loading or couldn't be fetched, so it can offer to try again:

```swift
if let product = entitlements.products(granting: .pro).first {
    BuyButton(product: product)
} else {
    switch PurchaseManager.shared.productsStatus {
        case .notLoaded, .loading:
            ProgressView()
        case .loaded:
            Text("Not available in your country")
        case .failed:
            Button("Try Again") { Task { await PurchaseManager.shared.refresh() } }
    }
}
```

### 5. Restore purchases

App Review expects a Restore Purchases button for anything that isn't consumable:

```swift
Button("Restore Purchases") {
    Task {
        do {
            try await PurchaseManager.shared.restore()
        } catch {
            // Show that restoring failed
        }
    }
}
```

`restore()` may ask the customer to sign in, so call it only from that button.

## Consumables

Non-consumables and subscriptions need no extra code: their access follows from their state. Consumables, like coins or a tip jar, are different: your app has to record each purchase. Add a transaction handler:

```swift
PurchaseManager.shared.setup(entitlements: AppEntitlement.self)
    .add(iap: "tip_small")
    .add(iap: "founders_pack", grants: .founder)
    .handleTransactions { transaction in
        guard transaction.productType == .consumable, transaction.revocationDate == nil else { return }
        try await Tips.record(transaction.id, quantity: transaction.purchasedQuantity)
    }
    .start()
```

- The handler sees every transaction. Return without doing anything for the ones you don't deliver.
- Return only after the purchase is saved durably. If the handler throws, the transaction stays unfinished and is retried later.
- Use `transaction.id` to make delivery idempotent: the same transaction can arrive more than once.

## Reacting outside views

For code that isn't a SwiftUI view, `stateUpdates` streams product states whenever they change, starting with the current ones:

```swift
Task {
    let entitlements = PurchaseManager.shared.entitlements(AppEntitlement.self)
    for await _ in PurchaseManager.shared.stateUpdates {
        game.setFounder(entitlements.isActive(.founder))
    }
}
```

## Trying paid features without buying

While developing, a debug menu can force entitlements on or off without a purchase. Allow overrides at setup, in debug builds only:

```swift
var setup = PurchaseManager.shared.setup(entitlements: AppEntitlement.self)
    .add(iap: "founders_pack", grants: .founder)
#if DEBUG
setup = setup.allowEntitlementOverrides()
#endif
setup.start()
```

Then set one with `setOverride(_:isActive:)`: `true` grants it, `false` withholds it (to see a purchased feature locked), and `nil` follows its products again:

```swift
Toggle("Own the Founder's Pack", isOn: Binding(
    get: { entitlements.override(for: .founder) == true },
    set: { entitlements.setOverride(.founder, isActive: $0 ? true : nil) }
))
```

Overrides are remembered between launches and apply only to entitlements: product states stay what StoreKit reports. A build that doesn't call `allowEntitlementOverrides()` ignores any stored overrides.

## Product states

Every product and entitlement has a `ProductState`:

| State | Meaning |
|---|---|
| `.active` | Access is granted. `expirationDate` is `nil` for permanent purchases. |
| `.expired` | A subscription ended. |
| `.revoked` | The purchase was refunded or revoked. |
| `.unknown` | No access could be established, including products that were never bought. |

An entitlement is active while any of its products is. Permanent access wins over expiring access; without access, the most recent expiration or revocation is reported.

## Setup options

| Option | What it does |
|---|---|
| `add(iap:grants:)`, `add(subscription:grants:)` | Register a product and the entitlements it grants. |
| `handleTransactions(using:)` | Deliver consumables and non-renewing subscriptions. |
| `cacheStates(in:key:)` | Show the last known states at launch until StoreKit reports. |
| `allowAccessDuringBillingRetry()` | Keep subscription access while Apple retries a failed payment. |
| `resolveNonRenewingSubscriptions(using:)` | Decide non-renewing subscription access from your own trusted data. |
| `refreshOnForeground(_:)` | Refresh when the app returns to the foreground. On by default. |
| `allowEntitlementOverrides(in:key:)` | Let a debug menu force entitlements on or off. Debug builds only. |
| `allowUnverifiedTransactions()` | Accept unverified transactions. For debugging only, never in production. |

## Testing

Test purchases in Xcode with a StoreKit configuration file (File → New → File → StoreKit Configuration File, synced from App Store Connect), selected in your scheme's Run options. PurchaseKit's own tests run with `swift test`.
