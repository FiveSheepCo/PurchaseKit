import Foundation

public struct ActiveProductState: Hashable {
    public let expirationDate: Date?

    public init(expirationDate: Date?) {
        self.expirationDate = expirationDate
    }
}
