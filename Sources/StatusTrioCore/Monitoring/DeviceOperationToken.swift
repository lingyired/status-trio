import Foundation

/// Identifies one current grant or operation without retaining retired IDs.
struct DeviceOperationToken: Equatable, Hashable, Sendable {
    private let value = UUID()
}
