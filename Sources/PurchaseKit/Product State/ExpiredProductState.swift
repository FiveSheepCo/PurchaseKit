import Foundation

public struct ExpiredProductState: Hashable, Sendable {
    public let expirationDate: Date

    public init(expirationDate: Date) {
        self.expirationDate = expirationDate
    }
}
