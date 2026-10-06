import Foundation
import StoreKit

extension ProductState {

    /// Resolve persistent access for an IAP without treating delivered quantities as ownership.
    static func resolveIAPState(
        for productType: StoreKit::Product.ProductType,
        revocation: RevokedProductState? = nil
    ) -> ProductState {
        // Consumable delivery and refunds belong to the app's transaction handler
        guard productType == .nonConsumable else { return .unknown }
        if let revocation { return .revoked(revocation) }
        return .active(ActiveProductState(expirationDate: nil))
    }
}
