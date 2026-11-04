import Foundation

extension PurchaseManager {

    /// Product states whenever they change, starting with the current states.
    ///
    /// Each access returns a new stream. A slow consumer only receives the newest states.
    public var stateUpdates: AsyncStream<[Product.ID: ProductState]> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: [Product.ID: ProductState].self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        self.stateContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stateContinuations[id] = nil }
        }
        continuation.yield(self.productStates)
        return stream
    }

    func publish(_ states: [Product.ID: ProductState]) {
        // Unchanged refreshes must not wake observers or stream consumers
        guard states != self.productStates else { return }
        self.productStates = states
        self.saveCachedStates()
        for continuation in self.stateContinuations.values {
            continuation.yield(states)
        }
    }
}
