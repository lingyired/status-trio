import Foundation

enum CustomAirPodsPreviewPreset: CaseIterable, Sendable {
    case both
    case leftOnly
    case rightOnly
    case unavailable
}

/// Settings-only battery input. This value is never persisted or sent to monitors.
struct CustomAirPodsPreviewSample: Equatable, Sendable {
    var leftAvailable = true
    var rightAvailable = true
    private(set) var leftBattery = 73
    private(set) var rightBattery = 68

    mutating func setLeftBattery(_ value: Double) {
        leftBattery = Self.clampedPercentage(value)
    }

    mutating func setRightBattery(_ value: Double) {
        rightBattery = Self.clampedPercentage(value)
    }

    mutating func apply(_ preset: CustomAirPodsPreviewPreset) {
        switch preset {
        case .both:
            leftAvailable = true
            rightAvailable = true
        case .leftOnly:
            leftAvailable = true
            rightAvailable = false
        case .rightOnly:
            leftAvailable = false
            rightAvailable = true
        case .unavailable:
            leftAvailable = false
            rightAvailable = false
        }
    }

    func batterySnapshot(now: Date) -> AirPodsBatteryIconSnapshot {
        AirPodsBatteryIconSnapshot(
            deviceAddress: "PREVIEW-CUSTOM-AIRPODS",
            model: .airPodsPro,
            main: nil,
            left: leftAvailable ? leftBattery : nil,
            right: rightAvailable ? rightBattery : nil,
            caseLevel: nil,
            observedAt: now
        )
    }

    var sourceAvailability: IconSourceAvailability {
        leftAvailable || rightAvailable ? .available : .unavailable(.unknown)
    }

    private static func clampedPercentage(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(min(100, max(0, value.rounded())))
    }
}
