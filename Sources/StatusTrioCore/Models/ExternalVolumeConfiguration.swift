import Foundation

enum ExternalVolumeBackend: String, Codable, CaseIterable, Sendable {
    case directDDC
    case betterDisplay
}

struct ExternalVolumeConfiguration: Codable, Equatable, Sendable {
    var backend: ExternalVolumeBackend
    var betterDisplayUUID: String?

    static let `default` = Self(
        backend: .directDDC,
        betterDisplayUUID: nil
    )

    func sanitized() -> Self? {
        switch backend {
        case .directDDC:
            return .default
        case .betterDisplay:
            let uuid = betterDisplayUUID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Self(
                backend: .betterDisplay,
                betterDisplayUUID: uuid?.isEmpty == false ? uuid : nil
            )
        }
    }
}
