import CoreGraphics
import Darwin
import Foundation
import os

private let displayServicesLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "DisplayServices"
)

/// One brightness observation for a built-in display.
struct DisplayServicesBrightnessUpdate: Equatable, Sendable {
    let displayID: UInt32
    /// 0...1, or nil when the value is unknown/unreadable.
    let scalar: Double?
    let canAdjust: Bool
    let source: BrightnessControlSource
}

/// Built-in display brightness through Apple's private `DisplayServices`
/// framework.
///
/// This is a maintainer-approved exception to the repository's usual
/// "no private APIs" rule: macOS has no public built-in brightness API, and the
/// alternative was requiring the user to install BetterDisplay. The framework is
/// loaded lazily with `dlopen`; if it or its symbols are missing the display is
/// reported unavailable instead of crashing.
///
/// The read/write calls are synchronous and cheap, so they run on the main
/// actor. Every failure is fail-closed; a write is only reported adjustable
/// after a read-back confirms it.
///
/// External changes (brightness keys, Control Center, Settings) are pushed by
/// `DisplayServicesRegisterForBrightnessChangeNotifications` rather than polled.
/// The callback only says "brightness changed"; the controller then reads the
/// new value back through the same fail-closed path as a manual refresh.
///
/// The narrow DisplayServices surface the brightness controller needs. A
/// protocol keeps read/write and change-notification behaviour testable without
/// touching the private framework in unit tests.
protocol DisplayServicesBrightnessAPI: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func getBrightness(
        _ displayID: CGDirectDisplayID,
        _ value: UnsafeMutablePointer<Float>
    ) -> Int32
    func setBrightness(_ displayID: CGDirectDisplayID, _ value: Float) -> Int32
    /// `observerID` identifies this subscription, independent of the display id.
    /// A previous controller must never unregister a newer controller's callback.
    func startBrightnessChangeNotifications(
        for displayID: CGDirectDisplayID, observerID: UInt32
    ) -> Bool
    func stopBrightnessChangeNotifications(for displayID: CGDirectDisplayID, observerID: UInt32)
}

/// Posted by the capture-free C callback. `object` is the subscription's
/// passthrough observer id as an `NSNumber`, rather than a CoreGraphics display
/// id. Old callbacks cannot reach a replacement controller after a restart.
extension Notification.Name {
    static let displayServicesBrightnessDidChange = Notification.Name(
        "com.lingsmbp.StatusTrio.displayServicesBrightnessDidChange"
    )
}

@MainActor
final class DisplayServicesBrightnessController {
    private let displayID: CGDirectDisplayID
    private let onUpdate: @MainActor (DisplayServicesBrightnessUpdate) -> Void
    private let api: any DisplayServicesBrightnessAPI
    private var isStarted = false
    private var notificationGeneration: UInt64 = 0
    private var brightnessObservation: DisplayServicesBrightnessObservation?
    private static var nextObserverID: UInt32 = 0

    /// Read-back tolerance: a built-in panel can quantize one step on a 0...1
    /// scale, so 2% absorbs that without hiding a real mismatch.
    private static let confirmationTolerance = 0.02

    init(
        displayID: CGDirectDisplayID,
        api: any DisplayServicesBrightnessAPI = DisplayServicesAPI.shared,
        onUpdate: @escaping @MainActor (DisplayServicesBrightnessUpdate) -> Void
    ) {
        self.displayID = displayID
        self.api = api
        self.onUpdate = onUpdate
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        startObservingBrightnessChanges()
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        notificationGeneration &+= 1
        // The token also unregisters if the controller is simply released.
        brightnessObservation = nil
    }

    /// Notifications exist only while the owning brightness surface is visible.
    /// No timer is added if this optional native registration is unavailable.
    private func startObservingBrightnessChanges() {
        guard displayID != 0, api.isAvailable else { return }
        Self.nextObserverID &+= 1
        if Self.nextObserverID == 0 { Self.nextObserverID &+= 1 }
        let observerID = Self.nextObserverID
        let generation = notificationGeneration
        let observer = NotificationCenter.default.addObserver(
            forName: .displayServicesBrightnessDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard (notification.object as? NSNumber)?.uint32Value == observerID else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isStarted,
                      self.notificationGeneration == generation else { return }
                self.refresh()
            }
        }
        guard api.startBrightnessChangeNotifications(for: displayID, observerID: observerID) else {
            NotificationCenter.default.removeObserver(observer)
            return
        }
        brightnessObservation = DisplayServicesBrightnessObservation(
            api: api, displayID: displayID, observerID: observerID, observer: observer
        )
    }

    func refresh() {
        guard isStarted else { return }
        // CGDirectDisplayID 0 is not "no display": CoreGraphics resolves it to
        // the built-in panel. Refuse it before touching the private API so an
        // unresolved external can never drive another screen.
        guard displayID != 0 else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.noBackend))
            return
        }
        guard api.isAvailable else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.noBackend))
            return
        }
        var value: Float = 0
        let status = api.getBrightness(displayID, &value)
        guard status == 0, value.isFinite else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.readFailed))
            return
        }
        emit(scalar: Double(min(1, max(0, value))), canAdjust: true, source: .displayServices)
    }

    func setBrightness(_ scalar: Double) {
        guard scalar.isFinite else { return }
        guard isStarted else { return }
        guard displayID != 0 else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.noBackend))
            return
        }
        guard api.isAvailable else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.noBackend))
            return
        }
        let target = Float(min(1, max(0, scalar)))
        guard api.setBrightness(displayID, target) == 0 else {
            emit(scalar: nil, canAdjust: false, source: .unavailable(.writeNotConfirmed))
            return
        }
        var value: Float = 0
        if api.getBrightness(displayID, &value) == 0,
           value.isFinite,
           abs(Double(value) - Double(target)) <= Self.confirmationTolerance {
            emit(scalar: Double(min(1, max(0, value))), canAdjust: true, source: .displayServices)
        } else {
            // The write was accepted; only the read-back has not confirmed it
            // yet (a lagging read) or could not be read. Keep the slider
            // adjustable with the accepted target instead of tearing it down
            // mid-gesture. A lagging read-back is corrected by the next change
            // notification; a *persistent* read failure is still surfaced by
            // refresh()/.readFailed. No retries, timers, or polling here.
            emit(scalar: Double(target), canAdjust: true, source: .displayServices)
        }
    }

    private func emit(
        scalar: Double?,
        canAdjust: Bool,
        source: BrightnessControlSource
    ) {
        onUpdate(
            DisplayServicesBrightnessUpdate(
                displayID: displayID,
                scalar: scalar,
                canAdjust: canAdjust,
                source: source
            )
        )
    }
}

/// Immutable subscription owner. NotificationCenter removal and the native
/// unregister operation are safe from teardown, without an actor-isolated
/// deinitializer or a task that extends the native subscription's lifetime.
private final class DisplayServicesBrightnessObservation {
    private let api: any DisplayServicesBrightnessAPI
    private let displayID: CGDirectDisplayID
    private let observerID: UInt32
    private let observer: NSObjectProtocol

    init(api: any DisplayServicesBrightnessAPI, displayID: CGDirectDisplayID,
         observerID: UInt32, observer: NSObjectProtocol) {
        self.api = api
        self.displayID = displayID
        self.observerID = observerID
        self.observer = observer
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
        api.stopBrightnessChangeNotifications(for: displayID, observerID: observerID)
    }
}

/// Lazily resolves the DisplayServices symbols. Immutable after init, so
/// `@unchecked Sendable` is safe.
private final class DisplayServicesAPI: DisplayServicesBrightnessAPI, @unchecked Sendable {
    typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias BrightnessChangeHandler = CFNotificationCallback
    typealias RegisterBrightnessChangeFn = @convention(c) (
        CGDirectDisplayID,
        UInt32,
        BrightnessChangeHandler
    ) -> Int32
    typealias UnregisterBrightnessChangeFn = @convention(c) (CGDirectDisplayID, UInt32) -> Int32

    static let shared = DisplayServicesAPI()

    private let getFunction: GetBrightnessFn?
    private let setFunction: SetBrightnessFn?
    private let registerBrightnessChangeFunction: RegisterBrightnessChangeFn?
    private let unregisterBrightnessChangeFunction: UnregisterBrightnessChangeFn?

    var isAvailable: Bool { getFunction != nil && setFunction != nil }

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else {
            getFunction = nil
            setFunction = nil
            registerBrightnessChangeFunction = nil
            unregisterBrightnessChangeFunction = nil
            return
        }
        getFunction = dlsym(handle, "DisplayServicesGetBrightness")
            .map { unsafeBitCast($0, to: GetBrightnessFn.self) }
        setFunction = dlsym(handle, "DisplayServicesSetBrightness")
            .map { unsafeBitCast($0, to: SetBrightnessFn.self) }
        registerBrightnessChangeFunction = dlsym(
            handle,
            "DisplayServicesRegisterForBrightnessChangeNotifications"
        ).map { unsafeBitCast($0, to: RegisterBrightnessChangeFn.self) }
        unregisterBrightnessChangeFunction = dlsym(
            handle,
            "DisplayServicesUnregisterForBrightnessChangeNotifications"
        ).map { unsafeBitCast($0, to: UnregisterBrightnessChangeFn.self) }
        if getFunction == nil || setFunction == nil {
            displayServicesLogger.notice("DisplayServices symbols unavailable")
        }
        // The handle is intentionally kept open for the process lifetime.
    }

    func getBrightness(
        _ displayID: CGDirectDisplayID,
        _ value: UnsafeMutablePointer<Float>
    ) -> Int32 {
        getFunction?(displayID, value) ?? -1
    }

    func setBrightness(_ displayID: CGDirectDisplayID, _ value: Float) -> Int32 {
        setFunction?(displayID, value) ?? -1
    }

    func startBrightnessChangeNotifications(
        for displayID: CGDirectDisplayID, observerID: UInt32
    ) -> Bool {
        // A registration without its stop function would leak native callbacks.
        guard let registerBrightnessChangeFunction,
              unregisterBrightnessChangeFunction != nil else { return false }
        return registerBrightnessChangeFunction(
            displayID, observerID, displayServicesBrightnessChanged
        ) == 0
    }

    func stopBrightnessChangeNotifications(for displayID: CGDirectDisplayID, observerID: UInt32) {
        _ = unregisterBrightnessChangeFunction?(displayID, observerID)
    }
}

/// DisplayServices uses CFNotificationCallback's argument order: the second
/// argument carries the observer id supplied at registration, not brightness.
private func displayServicesBrightnessChanged(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    // The API passes our registration passthrough back as the observer pointer.
    let raw = UInt(bitPattern: observer)
    guard raw <= UInt32.max else { return }
    NotificationCenter.default.post(
        name: .displayServicesBrightnessDidChange,
        object: NSNumber(value: UInt32(raw))
    )
}
