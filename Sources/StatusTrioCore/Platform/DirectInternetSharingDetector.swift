import Foundation
import SystemConfiguration

/// `com.apple.nat` is an undocumented dynamic-store key used only as a
/// best-effort signal. Missing or unreadable data returns `nil`, which means
/// "not definitively sharing" and never assumes sharing is active.
final class SystemInternetSharingDetector: InternetSharingDetecting, @unchecked Sendable {
    func isActive() -> Bool? {
        guard
            let store = SCDynamicStoreCreate(
                nil,
                "StatusTrio" as CFString,
                nil,
                nil
            ),
            let value = SCDynamicStoreCopyValue(
                store,
                "com.apple.nat" as CFString
            ) as? [String: Any],
            let nat = value["NAT"] as? [String: Any]
        else { return nil }

        return booleanValue(nat["Enabled"])
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? Int {
            return value == 1
        }
        return nil
    }
}
