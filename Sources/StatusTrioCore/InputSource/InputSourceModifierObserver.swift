import AppKit

struct InputSourceModifiers: Equatable, Sendable {
    var capsLock = false
    var shift = false

    var isUppercase: Bool { capsLock != shift }

    init(capsLock: Bool = false, shift: Bool = false) {
        self.capsLock = capsLock
        self.shift = shift
    }

    init(flags: NSEvent.ModifierFlags) {
        capsLock = flags.contains(.capsLock)
        shift = flags.contains(.shift)
    }
}

@MainActor
protocol InputSourceModifierObserving: AnyObject {
    func start(handler: @escaping @MainActor (InputSourceModifiers) -> Void)
    func stop()
}

/// Observes only modifier transitions, never key presses or typed characters.
/// No event tap, polling, permission prompt, or keyboard-event suppression.
@MainActor
final class SystemInputSourceModifierObserver: InputSourceModifierObserving {
    private var monitors: [InputSourceEventMonitor] = []
    private let systemEvents = SystemEventObserverBag()

    func start(handler: @escaping @MainActor (InputSourceModifiers) -> Void) {
        stop()
        handler(InputSourceModifiers(flags: NSEvent.modifierFlags))
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { event in
            let value = InputSourceModifiers(flags: event.modifierFlags)
            Task { @MainActor in handler(value) }
        }) {
            monitors.append(InputSourceEventMonitor(token))
        }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            let value = InputSourceModifiers(flags: event.modifierFlags)
            Task { @MainActor in handler(value) }
            return event
        }) {
            monitors.append(InputSourceEventMonitor(token))
        }
        systemEvents.install(applicationActivated: {
            Task { @MainActor in handler(InputSourceModifiers(flags: NSEvent.modifierFlags)) }
        }, didWake: {
            Task { @MainActor in handler(InputSourceModifiers(flags: NSEvent.modifierFlags)) }
        })
    }

    func stop() {
        monitors.removeAll()
        systemEvents.removeAll()
    }
}

/// AppKit monitor removal is thread-safe; owning the opaque token here ensures
/// registration is released even when the controller is torn down without stop.
private final class InputSourceEventMonitor {
    private let token: Any
    init(_ token: Any) { self.token = token }
    deinit { NSEvent.removeMonitor(token) }
}
