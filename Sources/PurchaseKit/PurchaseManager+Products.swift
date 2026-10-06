import Foundation
import StoreKit

extension PurchaseManager {

    func fetchProducts() async throws {
        var resolvedProducts: [Product] = []
        
        // Fetch registered products from StoreKit
        let registeredProductIds = self.registeredProducts.map(\.id)
        let skProducts = try await StoreKit.Product.products(for: registeredProductIds)
        
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
    }
}
