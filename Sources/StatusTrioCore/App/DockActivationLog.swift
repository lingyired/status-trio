import AppKit
import os

let dockActivationLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "DockActivation"
)

/// Event-time focus evidence shared by the Dock presentation and Settings
/// window lifecycle logs. This deliberately reads only current state; it does
/// not schedule follow-up sampling or change window ordering.
@MainActor
func dockActivationFocusSnapshot(window: NSWindow? = nil) -> String {
    let event = NSApp.currentEvent
    let eventType = event.map { String(describing: $0.type) } ?? "nil"
    let eventWindowNumber = event?.window?.windowNumber ?? 0
    let targetWindow = window ?? event?.window

    return """
    currentEvent=\(eventType) currentEventWindow=\(eventWindowNumber) \
    pressedMouseButtons=\(NSEvent.pressedMouseButtons) \
    applicationActive=\(NSApp.isActive) activationPolicy=\(NSApp.activationPolicy().rawValue) \
    keyWindow=\(NSApp.keyWindow?.windowNumber ?? 0) \
    mainWindow=\(NSApp.mainWindow?.windowNumber ?? 0) \
    targetWindow=\(targetWindow?.windowNumber ?? 0) \
    targetVisible=\(targetWindow?.isVisible ?? false) \
    targetKey=\(targetWindow?.isKeyWindow ?? false)
    """
}
