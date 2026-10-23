import Foundation

/// IOBluetooth exposes controller power as a read-only property, so changing it
/// requires the private preference symbols used by blueutil. Resolve them at
/// runtime so an OS that removes them degrades to Settings instead of failing
/// to launch.
final class IOBluetoothRadioPowerBackend: @unchecked Sendable, BluetoothRadioPowerBacking {
    typealias ReadPower = @convention(c) () -> Int32
    typealias SetPower = @convention(c) (Int32) -> Void
    typealias PreferencesAvailable = @convention(c) () -> Int32

    private static let frameworkPath =
        "/System/Library/Frameworks/IOBluetooth.framework/Versions/A/IOBluetooth"

    private let lock = NSLock()
    private let libraryHandle: UnsafeMutableRawPointer?
    private let readPowerSymbol: ReadPower?
    private let setPowerSymbol: SetPower?
    private let preferencesAvailableSymbol: PreferencesAvailable?

    struct Symbols {
        let readPower: ReadPower?
        let setPower: SetPower?
        let preferencesAvailable: PreferencesAvailable?
    }

    init(symbols: Symbols? = nil) {
        if let symbols {
            libraryHandle = nil
            readPowerSymbol = symbols.readPower
            setPowerSymbol = symbols.setPower
            preferencesAvailableSymbol = symbols.preferencesAvailable
        } else {
            let libraryHandle = Self.openFramework()
            self.libraryHandle = libraryHandle
            readPowerSymbol = Self.load("IOBluetoothPreferenceGetControllerPowerState", from: libraryHandle)
            setPowerSymbol = Self.load("IOBluetoothPreferenceSetControllerPowerState", from: libraryHandle)
            preferencesAvailableSymbol = Self.load("IOBluetoothPreferencesAvailable", from: libraryHandle)
        }
    }

    var isAvailable: Bool {
        guard readPowerSymbol != nil, setPowerSymbol != nil else {
            return false
        }
        return Self.isAvailable(preferencesAvailableSymbol)
    }

    func readPower() -> BluetoothRadioPower {
        guard isAvailable, let readPowerSymbol else { return .unavailable }
        switch readPowerSymbol() {
        case 0: return .off
        case 1: return .on
        default: return .unknown
        }
    }

    func setPower(_ enabled: Bool) async -> Bool {
        guard isAvailable, let setPowerSymbol else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                setPowerSymbol(enabled ? 1 : 0)
                continuation.resume(returning: true)
            }
        }
    }

    private static func openFramework() -> UnsafeMutableRawPointer? {
        dlopen(frameworkPath, RTLD_LAZY)
    }

    private static func load<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func isAvailable(_ symbol: PreferencesAvailable?) -> Bool {
        guard let symbol else { return true }
        return symbol() != 0
    }
}
