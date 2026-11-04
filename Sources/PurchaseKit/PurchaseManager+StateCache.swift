import Foundation

/// Where the manager keeps the last known product states between launches.
struct ProductStateCacheLocation {
    let defaults: UserDefaults
    let key: String
}

extension PurchaseManager {

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
