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
@MainActor
final class DisplayServicesBrightnessController {
    private let displayID: CGDirectDisplayID
    private let onUpdate: @MainActor (DisplayServicesBrightnessUpdate) -> Void
    private let api = DisplayServicesAPI.shared
    private var isStarted = false

    /// Read-back tolerance: a built-in panel can quantize one step on a 0...1
    /// scale, so 2% absorbs that without hiding a real mismatch.
    private static let confirmationTolerance = 0.02

    init(
        displayID: CGDirectDisplayID,
        onUpdate: @escaping @MainActor (DisplayServicesBrightnessUpdate) -> Void
    ) {
        self.displayID = displayID
        self.onUpdate = onUpdate
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refresh()
    }

    func stop() {
        isStarted = false
    }

    func refresh() {
        guard isStarted else { return }
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
        guard isStarted else { return }
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
            emit(scalar: nil, canAdjust: false, source: .unavailable(.writeNotConfirmed))
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

/// Lazily resolves the DisplayServices symbols. Immutable after init, so
/// `@unchecked Sendable` is safe.
private final class DisplayServicesAPI: @unchecked Sendable {
    typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let shared = DisplayServicesAPI()

    private let getFunction: GetBrightnessFn?
    private let setFunction: SetBrightnessFn?

    var isAvailable: Bool { getFunction != nil && setFunction != nil }

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else {
            getFunction = nil
            setFunction = nil
            return
        }
        getFunction = dlsym(handle, "DisplayServicesGetBrightness")
            .map { unsafeBitCast($0, to: GetBrightnessFn.self) }
        setFunction = dlsym(handle, "DisplayServicesSetBrightness")
            .map { unsafeBitCast($0, to: SetBrightnessFn.self) }
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
}
