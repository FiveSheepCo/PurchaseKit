# Security Policy

PurchaseKit decides which paid features a customer can use, so a bug in it can give away access or take away access someone paid for. Please report these privately.

## Reporting a vulnerability

Report it through [GitHub's private vulnerability reporting](https://github.com/FiveSheepCo/PurchaseKit/security/advisories/new). Please don't open a public issue or pull request for it.

Include what you can of:

- What happens, and what should happen instead.
- Steps or a test that reproduces it, for example with a StoreKit configuration file.
- The PurchaseKit commit or version, and the OS versions you tested on.

PurchaseKit is maintained by a small team, so we can't promise a response time, but we'll do our best to reply quickly and keep you updated while we work on a fix. We'll credit you in the advisory unless you'd rather not be named.

## Supported versions

PurchaseKit hasn't had a tagged release yet. Fixes go to `main`. Once versions are tagged, fixes go to the latest release.

## What counts

Examples of what we want to hear about:

- Access granted without a valid purchase, such as from an unverified transaction when `allowUnverifiedTransactions()` wasn't called.
- A refunded, revoked, upgraded, or expired purchase that keeps granting access.
- Entitlement overrides taking effect in a build that didn't call `allowEntitlementOverrides()`.
- A transaction finished before the app's transaction handler delivered it, so the purchase is lost.

Not in scope:

- Apps that enable `allowUnverifiedTransactions()` or `allowEntitlementOverrides()` in release builds. Both are documented as debug-only.
- Changing the app's binary or memory on a jailbroken or otherwise compromised device. PurchaseKit runs on the device and can't defend against that; verify purchases on your server if you need to.
