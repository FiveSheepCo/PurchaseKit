import Foundation
import StoreKit
import OSLog

public struct PurchaseManagerConfiguration {
    var allowUnverifiedTransactions: Bool = false
    var allowAccessDuringBillingRetry: Bool = false
}

@MainActor
public class PurchaseManager {
    public static let shared = PurchaseManager()
    
    let logger = Logger(subsystem: "PurchaseKit", category: "PurchaseManager")
    
    /// The task handling incoming transaction updates.
    var updateTask: Task<Void, Never>?
    
    /// Products that have been registered by the user and need to be fetched.
    var registeredProducts: [RegisteredProduct] = []
    
    /// Fully resolved and purchase-ready products.
    var products: [Product] = []
    
    /// The current state of each resolved product.
    var productStates: [Product.ID: ProductState] = [:]
    
    /// The purchase manager configuration.
    var config = PurchaseManagerConfiguration()
    
    public init() {}
    
    public func start() {
        setupUpdateTask()
    }
}
