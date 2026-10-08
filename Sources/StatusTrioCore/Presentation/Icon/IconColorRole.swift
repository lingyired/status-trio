import Foundation

enum IconColorRole: Equatable, Hashable, Sendable {
    static let inactiveTrackOpacity = 0.22

    case primary
    case inactive
    case critical
    case lowPower
    case powered
    case bluetooth
    case custom(IconRGBA)
}
