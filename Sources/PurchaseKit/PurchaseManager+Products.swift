import Foundation
import StoreKit

extension PurchaseManager {

    /// Fetch the registered products, reporting progress in `productsStatus`.
    ///
    /// A failed fetch keeps the products of an earlier one.
    func fetchProducts(
        using fetch: ([String]) async throws -> [StoreKit.Product] = { try await StoreKit.Product.products(for: $0) }
    ) async throws {
        var resolvedProducts: [Product] = []
        self.productsStatus = .loading

        // Fetch registered products from StoreKit
        let registeredProductIds = self.registeredProducts.map(\.id)
        let skProducts: [StoreKit.Product]
        do {
            skProducts = try await fetch(registeredProductIds)
        } catch {
            self.productsStatus = .failed
            throw error
        }

        for skProduct in skProducts {
            
            // Map StoreKit product to our product
            switch skProduct.type {
                case .autoRenewable, .nonRenewable:
                    let product = Product(skProduct: skProduct, kind: .subscription)
                    resolvedProducts.append(product)
                case .consumable, .nonConsumable:
                    let product = Product(skProduct: skProduct, kind: .iap)
                    resolvedProducts.append(product)
                default:
                    logger.error("Unsupported product type '\(skProduct.type.localizedDescription)' for product '\(skProduct.id)'")
                    continue
            }
        }

        self.products = resolvedProducts
        self.consumableProductIds.formUnion(resolvedProducts.filter(\.isConsumable).map(\.id))
        self.productsStatus = .loaded
    }
}
