import Foundation

public struct ActiveProductState: Hashable, Sendable {
    /// The access expiration date, if known. This is also nil for permanent purchases.
    public let expirationDate: Date?

    public init(expirationDate: Date?) {
        self.expirationDate = expirationDate
    }
}
