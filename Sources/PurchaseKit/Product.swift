import Foundation
import StoreKit

public struct Product: Identifiable, Sendable {
    public let skProduct: StoreKit.Product
    public let kind: ProductKind
    
    /// The StoreKit product identifier.
    public var id: String {
        skProduct.id
    }
    
    /// Whether the product is a renewable subscription.
    public var isRenewable: Bool {
        switch skProduct.type {
            case .autoRenewable: true
            default: false
        }
    }
    
    /// Whether the product is a consumable IAP.
    public var isConsumable: Bool {
        switch skProduct.type {
            case .consumable: true
            default: false
        }
    }
    
    package init(skProduct: StoreKit.Product, kind: ProductKind) {
        self.skProduct = skProduct
        self.kind = kind
    }
}
