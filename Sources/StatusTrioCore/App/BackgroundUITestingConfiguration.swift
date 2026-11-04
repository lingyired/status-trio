import AppKit

/// Immutable launch configuration. Release builds do not interpret test flags.
struct BackgroundUITestingConfiguration: Equatable, Sendable {
    enum Display: String, Sendable {
        case automatic
        case secondary
    }

    let isEnabled: Bool
    let display: Display
    let opensStatusPanel: Bool
    let diagnostics: [String]

    var rejectsLaunch: Bool { !diagnostics.isEmpty }

    static let disabled = Self(arguments: [])

    init(arguments: [String]) {
        #if DEBUG
        let enabledCount = arguments.filter { $0 == "--background-ui-testing" }.count
        let displays = arguments.filter { $0.hasPrefix("--test-display") }
        let statusPanelArguments = arguments.filter { $0.hasPrefix("--test-open-status-panel") }
        var problems = arguments.filter {
            $0.hasPrefix("--background-ui-testing") && $0 != "--background-ui-testing"
        }.map { "Unknown background UI testing argument: \($0)" }
        if enabledCount > 1 {
            problems.append("Duplicate --background-ui-testing.")
        }
        if displays.count > 1 || displays.contains(where: { $0 != "--test-display=secondary" }) {
            problems.append("Expected at most one --test-display=secondary.")
        }
        if !displays.isEmpty, enabledCount == 0 {
            problems.append("--test-display requires --background-ui-testing.")
        }
        if statusPanelArguments.count > 1
            || statusPanelArguments.contains(where: { $0 != "--test-open-status-panel" }) {
            problems.append("Expected at most one --test-open-status-panel.")
        }
        if !statusPanelArguments.isEmpty, enabledCount == 0 {
            problems.append("--test-open-status-panel requires --background-ui-testing.")
        }
        isEnabled = enabledCount == 1 && problems.isEmpty
        display = isEnabled && !displays.isEmpty ? .secondary : .automatic
        opensStatusPanel = isEnabled && statusPanelArguments.count == 1
        diagnostics = problems
        #else
        isEnabled = false
        display = .automatic
        opensStatusPanel = false
        diagnostics = []
        #endif
    }
}

enum SettingsWindowPresentation: Equatable {
    case activating
    case background

    @MainActor
    func present(_ window: NSWindow) {
        switch self {
        case .activating:
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        case .background:
            window.orderFront(nil)
        }
    }
}

struct UITestingScreen: Equatable {
    let displayID: CGDirectDisplayID
    let visibleFrame: NSRect
}

enum BackgroundUIWindowPlacement {
    /// Re-evaluated on presentation; no display observer or idle work is needed.
    static func frame(
        current: NSRect,
        display: BackgroundUITestingConfiguration.Display,
        screens: [UITestingScreen],
        mainDisplayID: CGDirectDisplayID
    ) -> NSRect? {
        let screens = screens.filter { $0.visibleFrame.width > 0 && $0.visibleFrame.height > 0 }
        let primary = screens.first { $0.displayID == mainDisplayID } ?? screens.first
        let secondary = screens.filter { $0.displayID != mainDisplayID }
            .sorted { $0.displayID < $1.displayID }.first
        let containing = screens.first { $0.visibleFrame.contains(NSPoint(x: current.midX, y: current.midY)) }
        guard let screen = display == .secondary ? (secondary ?? primary) : (containing ?? primary) else {
            return nil
        }
        let visible = screen.visibleFrame
        var origin = current.origin
        if !visible.contains(NSPoint(x: current.midX, y: current.midY)) {
            origin = NSPoint(x: visible.midX - current.width / 2, y: visible.midY - current.height / 2)
        }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - current.width))
        // When the fixed-size UI exceeds a display, keep its title bar reachable.
        origin.y = min(visible.maxY - current.height, max(origin.y, visible.minY))
        return NSRect(origin: origin, size: current.size)
    }

    @MainActor
    static func position(_ window: NSWindow, display: BackgroundUITestingConfiguration.Display) {
        let screens = NSScreen.screens.map { screen in
            UITestingScreen(
                displayID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber)?.uint32Value ?? 0,
                visibleFrame: screen.visibleFrame
            )
        }
        guard let frame = frame(
            current: window.frame, display: display, screens: screens, mainDisplayID: CGMainDisplayID()
        ) else { return }
        window.setFrame(frame, display: false)
    }
}
