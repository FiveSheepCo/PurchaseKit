import Foundation

public struct ExpiredProductState: Hashable {
    public let expirationDate: Date

    public init(expirationDate: Date) {
        self.expirationDate = expirationDate
    }
}
