import Foundation

/// Where fetching the registered products from the App Store stands.
///
/// A store shows a product once it's in `products`, and otherwise uses this to tell
/// "still loading" from "couldn't load", where it can offer to try again with `refresh()`.
public enum ProductsStatus: Hashable, Sendable {
    /// The manager hasn't started fetching yet.
    case notLoaded
    /// A fetch is running. Products from an earlier fetch stay available meanwhile.
    case loading
    /// The latest fetch succeeded. Products the App Store doesn't know are missing from `products`.
    case loaded
    /// The latest fetch failed, for example without a network connection.
    /// Products from an earlier fetch stay available.
    case failed
}
