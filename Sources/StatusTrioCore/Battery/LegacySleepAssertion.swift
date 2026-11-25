import Foundation
import IOKit.pwr_mgt

/// Holds the power assertions that keep the Mac awake while a legacy charge
/// ceiling is still being reached (the "keep awake until limit" sleep policy).
///
/// There is deliberately no timer: the caller acquires/releases on the battery
/// events that already drive the limiter, and `stop()` always releases. The
/// display still turns off when the lid closes; only system sleep is deferred.
final class LegacySleepAssertion: @unchecked Sendable {
    private let lock = NSLock()
    private var idleAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0

    var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return idleAssertion != 0 || systemAssertion != 0
    }

    func acquire(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        guard idleAssertion == 0, systemAssertion == 0 else { return }
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            level,
            reason as CFString,
            &idleAssertion
        )
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            level,
            reason as CFString,
            &systemAssertion
        )
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        if idleAssertion != 0 { IOPMAssertionRelease(idleAssertion); idleAssertion = 0 }
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
    }

    deinit { release() }
}
