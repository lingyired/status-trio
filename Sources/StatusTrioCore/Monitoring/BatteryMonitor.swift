import Foundation
import IOKit.ps
import OSLog

private let batteryMonitorLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "battery"
)

struct BatteryReading: Equatable {
    var currentCapacity: Int
    var maxCapacity: Int
    var isCharging: Bool
    var isCharged: Bool = false
    var timeToFullChargeMinutes: Int? = nil
    var timeToEmptyMinutes: Int? = nil
    var isConnectedToPower: Bool
    var isPresent: Bool
}

protocol BatteryReadingProviding: AnyObject {
    func read() -> BatteryReading?
}

typealias IOPSNotificationCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias IOPSRunLoopSourceFactory = (
    UnsafeMutableRawPointer?,
    IOPSNotificationCallback
) -> CFRunLoopSource?

private final class BatteryCallbackContext: @unchecked Sendable {
    weak var monitor: BatteryMonitor?

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
    }
}

final class IOPSBatteryReader: BatteryReadingProviding {
    func read() -> BatteryReading? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                let reading = Self.parse(description)
            else { continue }

            return reading
        }

        return nil
    }

    static func parse(_ description: [String: Any]) -> BatteryReading? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
            return nil
        }
        guard
            let current = integerValue(description[kIOPSCurrentCapacityKey]),
            let maximum = integerValue(description[kIOPSMaxCapacityKey])
        else { return nil }

        let rawTimeToFullCharge = integerValue(description[kIOPSTimeToFullChargeKey])
        let timeToFullCharge = rawTimeToFullCharge.flatMap { $0 > 0 ? $0 : nil }

        let timeToEmpty = integerValue(description[kIOPSTimeToEmptyKey])
            .flatMap { $0 > 0 ? $0 : nil }

        return BatteryReading(
            currentCapacity: current,
            maxCapacity: maximum,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
            timeToFullChargeMinutes: timeToFullCharge,
            timeToEmptyMinutes: timeToEmpty,
            isConnectedToPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            isPresent: description[kIOPSIsPresentKey] as? Bool ?? true
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

@MainActor
final class BatteryMonitor: BatteryMonitoring {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    private let reader: any BatteryReadingProviding
    private let lowPowerModeProvider: () -> Bool
    private let iopsRunLoopSourceFactory: IOPSRunLoopSourceFactory
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var lowPowerObserver: NSObjectProtocol?
    nonisolated(unsafe) private var callbackContext: Unmanaged<BatteryCallbackContext>?
    private var lifecycle = Lifecycle.idle

    init(
        reader: any BatteryReadingProviding = IOPSBatteryReader(),
        lowPowerModeProvider: @escaping () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        },
        iopsRunLoopSourceFactory: @escaping IOPSRunLoopSourceFactory = { context, callback in
            IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
        }
    ) {
        self.reader = reader
        self.lowPowerModeProvider = lowPowerModeProvider
        self.iopsRunLoopSourceFactory = iopsRunLoopSourceFactory
        (updates, continuation) = MonitorStream.make(of: BatteryStatus.self)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        if let callbackContext {
            callbackContext.release()
        }
        continuation.finish()
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running

        installNotifications()
        refresh()
    }

    func recover() {
        guard lifecycle == .running else { return }

        teardownNotifications()
        installNotifications()
    }

    private func installNotifications() {

        let context = Unmanaged.passRetained(BatteryCallbackContext(monitor: self))
        callbackContext = context

        let callback: IOPSNotificationCallback = { contextPointer in
            guard let contextPointer else { return }
            let callbackContext = Unmanaged<BatteryCallbackContext>
                .fromOpaque(contextPointer)
                .takeUnretainedValue()
            guard let monitor = callbackContext.monitor else { return }
            Task { @MainActor in
                monitor.refresh()
            }
        }

        if let source = iopsRunLoopSourceFactory(context.toOpaque(), callback) {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            batteryMonitorLogger.error(
                "IOPS notification source unavailable; fallback refresh remains active"
            )
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        teardownNotifications()
        continuation.finish()
    }

    func refresh() {
        guard lifecycle != .stopped else { return }

        let reading = reader.read()
        let status: BatteryStatus

        if let reading, reading.isPresent {
            let percentage = reading.maxCapacity > 0
                ? Int((Double(reading.currentCapacity) / Double(reading.maxCapacity) * 100).rounded())
                : reading.currentCapacity
            status = BatteryStatus(
                rawPercentage: percentage,
                isPresent: true,
                isCharging: reading.isCharging,
                isCharged: reading.isCharged,
                timeToFullChargeMinutes: reading.isCharging
                    ? reading.timeToFullChargeMinutes
                    : nil,
                // IOKit runtime estimates are valid only while discharging.
                timeToEmptyMinutes: !reading.isConnectedToPower && !reading.isCharging
                    ? reading.timeToEmptyMinutes.flatMap { $0 > 0 ? $0 : nil }
                    : nil,
                isLowPowerMode: lowPowerModeProvider(),
                isConnectedToPower: reading.isConnectedToPower
            )
        } else {
            status = BatteryStatus(
                rawPercentage: nil,
                isPresent: false,
                isCharging: false,
                isCharged: false,
                timeToFullChargeMinutes: nil,
                isLowPowerMode: lowPowerModeProvider(),
                isConnectedToPower: false
            )
        }

        continuation.yield(status)
    }

    private func teardownNotifications() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        if let callbackContext {
            callbackContext.release()
            self.callbackContext = nil
        }
    }
}
