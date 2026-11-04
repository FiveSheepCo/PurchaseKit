import Foundation

extension PurchaseManager {

    /// The fetched product with the given identifier, if StoreKit returned it.
    public func product(for id: Product.ID) -> Product? {
        self.products.first { $0.id == id }
    }

    /// The current access state of a product.
    ///
    /// Products without established access, including consumables, are `.unknown`.
    public func state(for productId: Product.ID) -> ProductState {
        self.productStates[productId] ?? .unknown
    }

    /// Whether the product currently grants access.
    public func isActive(_ productId: Product.ID) -> Bool {
        self.state(for: productId).isActive
    }
}
