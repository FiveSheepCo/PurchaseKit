import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension PurchaseManager {

    /// Posted when the app comes back to the foreground. StoreKit may have news by then, such as
    /// a refund or a Family Sharing change made while the app was away.
    static var foregroundNotification: Notification.Name? {
        #if canImport(UIKit)
        UIApplication.willEnterForegroundNotification
        #elseif canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        nil
        #endif
    }

    /// Run `refresh` each time `name` is posted, until the manager goes away.
    func setupForegroundRefreshTask(
        observing name: Notification.Name?,
        refresh: @escaping @MainActor () async -> Void
    ) {
        guard self.foregroundRefreshTask == nil, let name else { return }
        self.foregroundRefreshTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                guard self != nil, !Task.isCancelled else { return }
                await refresh()
            }
        }
    }
}
