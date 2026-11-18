import AppKit
import ApplicationServices

/// Resolves which app owns each menu bar item, reads live item frames, and
/// triggers items (or macOS 27's native `«` overflow button) via Accessibility.
enum MenuBarAccessibility {
    struct AppCandidate: Sendable {
        let pid: pid_t
        let name: String
        let bundleIdentifier: String?
    }

    private static let messagingTimeout: Float = 0.12
    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.Siri",
        "com.apple.MenuBarAgent"
    ]

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func candidates(excluding ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [AppCandidate] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ownPID,
                  app.activationPolicy != .prohibited,
                  !app.isTerminated else { return nil }
            if let bundleID = app.bundleIdentifier,
               excludedBundleIdentifiers.contains(bundleID) {
                return nil
            }
            return AppCandidate(
                pid: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "",
                bundleIdentifier: app.bundleIdentifier
            )
        }
    }

    /// Reads every candidate's `AXExtrasMenuBar` items. Blocking; call off the main actor.
    static func resolveOwners(_ candidates: [AppCandidate]) -> [MenuBarItemOwner] {
        var owners: [MenuBarItemOwner] = []
        for candidate in candidates {
            let elements = extrasElements(pid: candidate.pid)
            for (index, element) in elements.enumerated() {
                let itemFrame = frame(of: element)
                    ?? CGRect(x: CGFloat(-1000 - index * 32), y: 0, width: 28, height: 24)
                owners.append(MenuBarItemOwner(
                    pid: candidate.pid,
                    elementIndex: index,
                    appName: candidate.name,
                    bundleIdentifier: candidate.bundleIdentifier,
                    frame: itemFrame
                ))
            }
        }
        return owners
    }

    static func liveFrame(for owner: MenuBarItemOwner) -> CGRect? {
        let elements = extrasElements(pid: owner.pid)
        guard !elements.isEmpty else { return nil }
        if elements.indices.contains(owner.elementIndex),
           let current = frame(of: elements[owner.elementIndex]),
           current.width > 1, current.height > 1 {
            return current
        }
        for element in elements {
            if let current = frame(of: element),
               current.width > 1, current.height > 1 {
                return current
            }
        }
        return nil
    }

    /// On macOS 27 (`MenuBarAgent`), collapsed overflow items are detached from
    /// `AXExtrasMenuBar` until the native `«` button (`menu-bar-overflow-indicator`)
    /// is expanded. Pressing it reveals the hidden items so their menus can open.
    @MainActor
    @discardableResult
    static func expandSystemOverflowIfNeeded() -> Bool {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent"
                || $0.localizedName == "MenuBarAgent"
        }) else { return false }

        let root = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let button = findOverflowButton(in: root, depth: 0) else { return false }
        return AXUIElementPerformAction(button, "AXPress" as CFString) == .success
    }

    @discardableResult
    static func performAction(
        owner: MenuBarItemOwner,
        click: MenuBarTrayClick = .left
    ) -> Bool {
        let elements = extrasElements(pid: owner.pid)
        guard !elements.isEmpty else { return false }
        let target: AXUIElement
        if elements.indices.contains(owner.elementIndex) {
            target = elements[owner.elementIndex]
        } else if let matched = elements.first(where: {
            guard let f = frame(of: $0) else { return false }
            return abs(f.minX - owner.frame.minX) <= 4
        }) {
            target = matched
        } else {
            target = elements[0]
        }

        let actions = click == .right
            ? ["AXShowMenu", "AXPress"]
            : ["AXPress", "AXShowMenu"]
        for action in actions {
            if AXUIElementPerformAction(target, action as CFString) == .success {
                return true
            }
        }
        return false
    }

    // MARK: - AX plumbing

    private static func findOverflowButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 6 else { return nil }
        var idRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &idRef) == .success,
           let id = idRef as? String,
           id == "menu-bar-overflow-indicator" {
            return element
        }
        for attr in ["AXChildren", "AXWindows", "AXExtrasMenuBar"] {
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    if let found = findOverflowButton(in: child, depth: depth + 1) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    private static func extrasElements(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        if let bar = element(app, attribute: "AXExtrasMenuBar") {
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(bar, "AXChildren" as CFString, &children) == .success,
               let list = children as? [AXUIElement], !list.isEmpty {
                return list
            }
        }
        return []
    }

    private static func element(_ parent: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXPosition" as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
