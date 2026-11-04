import Foundation

/// Where the manager keeps the last known product states between launches.
struct ProductStateCacheLocation {
    let defaults: UserDefaults
    let key: String
}

extension PurchaseManager {

    /// Show the last known product states at launch until the first refresh completes.
    ///
    /// StoreKit needs a moment after launch to report entitlements; without this, paid
    /// content appears locked until it does. The stored states are only for display:
    /// every refresh replaces them with StoreKit's.
    @discardableResult
    public func cacheStates(in defaults: UserDefaults = .standard, key: String = "PurchaseKit.productStates") -> Self {
        self.config.stateCacheLocation = ProductStateCacheLocation(defaults: defaults, key: key)
        return self
    }

    func loadCachedStates() {
        // A completed or running refresh is newer than anything stored
        guard self.stateRefreshVersion == 0,
              let location = self.config.stateCacheLocation,
              let data = location.defaults.data(forKey: location.key) else { return }
        do {
            let cachedStates = try JSONDecoder().decode([Product.ID: CachedProductState].self, from: data)
            self.publish(cachedStates.mapValues(\.state).filter { $0.value != .unknown })
        } catch {
            self.logger.error("Failed to load cached product states: \(error)")
        }
    }

    func saveCachedStates() {
        guard let location = self.config.stateCacheLocation else { return }
        do {
            let data = try JSONEncoder().encode(self.productStates.compactMapValues(CachedProductState.init))
            location.defaults.set(data, forKey: location.key)
        } catch {
            self.logger.error("Failed to save cached product states: \(error)")
        }
    }
}
