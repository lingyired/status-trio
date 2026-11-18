import AppKit

/// The menu bar item that splits visible items from hidden ones.
///
/// Items to its left are "in the tray". On macOS 13–26 collapsing stretches it
/// to a large length to push items off-screen; on macOS 27 (`MenuBarAgent`) an
/// item wider than the space to the right of the Notch is itself evicted into
/// the system overflow menu, so `collapse()` sizes the separator to fill the
/// exact space between its current right edge and the Notch / status-bar left
/// boundary.
@MainActor
final class MenuBarSeparatorController: NSObject {
    static let legacyCollapsedLength: CGFloat = 10_000
    static let autosaveName = "StatusTrioMenuBarTraySeparator"

    var onClick: (() -> Void)?
    var helpText: String = "" {
        didSet { item?.button?.toolTip = helpText }
    }

    private var item: NSStatusItem?
    private(set) var isCollapsed = false
    /// Records the separator's right-edge global X before collapsing so
    /// scanners know where the divider sits even if the OS resizes it.
    private(set) var anchorMaxX: CGFloat?

    var isInstalled: Bool { item != nil }

    private static let collapsedPlaceholderImage: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.isTemplate = true
        return image
    }()

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.toolTip = helpText
        }
        self.item = item
        applyExpandedAppearance()
        isCollapsed = false
    }

    func uninstall() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        isCollapsed = false
        anchorMaxX = nil
    }

    func collapse() {
        guard let item else { return }
        // Measure the expanded right edge first so we know how far to the
        // Notch / status-bar boundary the separator can expand without being
        // evicted by macOS 27's MenuBarAgent.
        if !isCollapsed, let window = item.button?.window, window.frame.width > 0 {
            anchorMaxX = window.frame.maxX
        }
        let maxX = anchorMaxX ?? item.button?.window?.frame.maxX ?? 0
        let screen = item.button?.window?.screen ?? NSScreen.main
        let length = Self.collapsedLength(forMaxX: maxX, on: screen)

        item.button?.title = ""
        item.button?.image = Self.collapsedPlaceholderImage
        item.length = length
        isCollapsed = true

        // If macOS 27's native `«` overflow button (~38pt) appeared when the
        // icons were pushed into overflow, the separator's left edge may have
        // crossed `auxiliaryTopRightArea.minX` and been clamped to the left of
        // the Notch. Trim by the `«` button width if needed.
        if let topRight = screen?.auxiliaryTopRightArea, maxX > topRight.minX + 52 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.isCollapsed,
                      let currentItem = self.item,
                      let window = currentItem.button?.window else { return }
                if window.frame.minX < topRight.minX - 2 {
                    let trimmed = max(24, floor(maxX - topRight.minX - 44))
                    currentItem.length = trimmed
                }
            }
        }
    }

    static func collapsedLength(forMaxX maxX: CGFloat, on screen: NSScreen?) -> CGFloat {
        if let topRight = screen?.auxiliaryTopRightArea, maxX > topRight.minX + 16 {
            return max(24, floor(maxX - topRight.minX))
        }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
           let screenFrame = screen?.frame,
           maxX > screenFrame.midX {
            return max(24, floor(maxX - screenFrame.midX))
        }
        return legacyCollapsedLength
    }

    func expand() {
        guard item != nil else { return }
        applyExpandedAppearance()
        isCollapsed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !self.isCollapsed,
                  let window = self.item?.button?.window,
                  window.frame.width > 0 else { return }
            self.anchorMaxX = window.frame.maxX
        }
    }

    var windowID: CGWindowID? {
        guard let number = item?.button?.window?.windowNumber else { return nil }
        return Self.validWindowID(fromWindowNumber: number)
    }

    static func validWindowID(fromWindowNumber number: Int) -> CGWindowID? {
        guard number > 0, let id = CGWindowID(exactly: number) else { return nil }
        return id
    }

    /// The separator's frame in global CoreGraphics coordinates.
    var globalFrame: CGRect? {
        guard let window = item?.button?.window,
              window.frame.width > 0,
              window.frame.height > 0 else { return nil }
        return Self.globalFrame(ofAppKitFrame: window.frame)
    }

    /// Converts an AppKit screen frame (bottom-left origin) into the window
    /// server's global space (top-left origin of the primary display).
    static func globalFrame(ofAppKitFrame frame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
        return CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func applyExpandedAppearance() {
        guard let item else { return }
        item.length = NSStatusItem.variableLength
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: helpText)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        item.button?.image = image
    }

    @objc private func handleClick(_ sender: Any?) {
        onClick?()
    }
}

/// Synthesises a real mouse click on a menu bar item. Requires Accessibility.
enum MenuBarClickPoster {
    static func post(_ click: MenuBarTrayClick, at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        let (downType, upType, button): (CGEventType, CGEventType, CGMouseButton) = switch click {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
        if let original {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                CGWarpMouseCursorPosition(original)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }
}
