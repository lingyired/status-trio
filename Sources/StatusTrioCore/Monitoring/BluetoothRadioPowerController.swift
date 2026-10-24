import Foundation

enum BluetoothRadioPower: Equatable, Sendable {
    case on
    case off
    case unavailable
    case unknown

    var isOn: Bool { self == .on }
}

enum BluetoothRadioPowerFailure: Equatable, Sendable {
    case requestRejected
    case stateDidNotChange
}

@MainActor
protocol BluetoothRadioPowerBacking: AnyObject {
    var isAvailable: Bool { get }
    func readPower() -> BluetoothRadioPower
    func setPower(_ enabled: Bool) async -> Bool
}

enum BluetoothRadioPowerPolicy {
    static func requiresConfirmation(beforeTurningOff devices: [BluetoothDevice]) -> Bool {
        devices.contains {
            $0.isConnected
                && ($0.kind.isPeripheral || $0.kind == .unknown)
        }
    }
}

struct BluetoothRadioPowerPresentation: Equatable, Sendable {
    let showsToggle: Bool
    let isOn: Bool
    let toggleEnabled: Bool
    let subtitle: String?
    let iconState: BluetoothRadioPowerIconState
    let accessibilityValue: String

    /// The outline power glyph keeps the same visual weight as the Low Power
    /// Mode leaf without implying a filled control or a circular button.
    var symbolName: String { "power" }

    @MainActor
    static func make(
        power: BluetoothRadioPower,
        isChanging: Bool,
        failure: BluetoothRadioPowerFailure?,
        localization: Localization
    ) -> Self {
        switch power {
        case .unavailable:
            return Self(
                showsToggle: false,
                isOn: false,
                toggleEnabled: false,
                subtitle: nil,
                iconState: .unavailable,
                accessibilityValue: localization.string(.bluetoothPowerUnknown)
            )
        case .unknown:
            return Self(
                showsToggle: true,
                isOn: false,
                toggleEnabled: !isChanging,
                subtitle: localization.string(.bluetoothPowerUnknown),
                iconState: .unknown,
                accessibilityValue: localization.string(.bluetoothPowerUnknown)
            )
        case .off:
            return Self(
                showsToggle: true,
                isOn: false,
                toggleEnabled: !isChanging,
                subtitle: failure != nil
                    ? localization.string(.bluetoothPowerChangeFailed)
                    : localization.string(.bluetoothOff),
                iconState: .off,
                accessibilityValue: localization.string(.batteryDetailsOff)
            )
        case .on:
            let failed = failure != nil
            return Self(
                showsToggle: true,
                isOn: true,
                toggleEnabled: !isChanging,
                subtitle: failed
                    ? localization.string(.bluetoothPowerChangeFailed)
                    : nil,
                iconState: .on,
                accessibilityValue: localization.string(.batteryDetailsOn)
            )
        }
    }
}

enum BluetoothRadioPowerIconState: Equatable, Sendable {
    case on
    case off
    case unknown
    case unavailable
}

@MainActor
final class BluetoothRadioPowerController: ObservableObject {
    static let defaultReadBackAttempts = 12
    static let defaultReadBackInterval: Duration = .milliseconds(250)

    @Published private(set) var power: BluetoothRadioPower
    @Published private(set) var isChanging = false
    @Published private(set) var failure: BluetoothRadioPowerFailure?

    private var backend: (any BluetoothRadioPowerBacking)?
    private let backendFactory: @MainActor () -> any BluetoothRadioPowerBacking
    private let sleep: @Sendable (Duration) async throws -> Void
    private let readBackAttempts: Int
    private let readBackInterval: Duration

    init(
        backend: any BluetoothRadioPowerBacking,
        readBackAttempts: Int = defaultReadBackAttempts,
        readBackInterval: Duration = defaultReadBackInterval,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.backend = backend
        backendFactory = { backend }
        self.readBackAttempts = max(1, readBackAttempts)
        self.readBackInterval = readBackInterval
        self.sleep = sleep
        power = .unknown
    }

    init(
        backendFactory: @escaping @MainActor () -> any BluetoothRadioPowerBacking,
        readBackAttempts: Int = defaultReadBackAttempts,
        readBackInterval: Duration = defaultReadBackInterval,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        backend = nil
        self.backendFactory = backendFactory
        self.readBackAttempts = max(1, readBackAttempts)
        self.readBackInterval = readBackInterval
        self.sleep = sleep
        power = .unknown
    }

    convenience init() {
        self.init(backendFactory: { UnavailableBluetoothRadioPowerBackend() })
    }

    var canSetPower: Bool {
        backend?.isAvailable == true && !isChanging
    }

    func refresh() {
        power = resolvedBackend().readPower()
    }

    @discardableResult
    func setPower(_ enabled: Bool) async -> Bool {
        let backend = resolvedBackend()
        guard backend.isAvailable else {
            power = .unavailable
            return false
        }
        guard !isChanging else { return false }
        isChanging = true
        failure = nil
        defer { isChanging = false }

        guard await backend.setPower(enabled) else {
            failure = .requestRejected
            refresh()
            return false
        }

        let expected: BluetoothRadioPower = enabled ? .on : .off
        for attempt in 0..<readBackAttempts {
            refresh()
            if power == expected {
                return true
            }
            guard attempt + 1 < readBackAttempts else { break }
            do {
                try await sleep(readBackInterval)
            } catch {
                break
            }
        }

        failure = .stateDidNotChange
        return false
    }

    private func resolvedBackend() -> any BluetoothRadioPowerBacking {
        if let backend {
            return backend
        }
        let backend = backendFactory()
        self.backend = backend
        return backend
    }
}

@MainActor
final class UnavailableBluetoothRadioPowerBackend: BluetoothRadioPowerBacking {
    let isAvailable = false
    func readPower() -> BluetoothRadioPower { .unavailable }
    func setPower(_ enabled: Bool) async -> Bool { false }
}
