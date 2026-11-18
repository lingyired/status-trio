import AppKit
import Carbon
import CoreGraphics

/// One menu bar item window as reported by the window server.
struct MenuBarWindowInfo: Equatable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let frame: CGRect
    let layer: Int
    let isOnScreen: Bool
}

/// The app that owns a menu bar item, resolved through Accessibility.
struct MenuBarItemOwner: Equatable, Sendable {
    let pid: pid_t
    let elementIndex: Int
    let appName: String
    let bundleIdentifier: String?
    /// Global top-left-origin frame reported by `AXPosition` / `AXSize`.
    let frame: CGRect

    var syntheticID: CGWindowID {
        let raw = (UInt64(UInt32(bitPattern: pid)) &* 31) &+ UInt64(UInt32(clamping: elementIndex + 1))
        return CGWindowID(truncatingIfNeeded: raw | 0x8000_0000)
    }
}

/// One hidden item shown in the panel's tray card.
struct MenuBarTrayItem: Identifiable, Equatable {
    let windowID: CGWindowID
    let frame: CGRect
    let owner: MenuBarItemOwner?
    let snapshot: MenuBarItemSnapshot?

    var id: CGWindowID { windowID }

    var isInputMethodAgent: Bool {
        owner?.bundleIdentifier == "com.apple.TextInputMenuAgent"
            || owner?.appName == "TextInputMenuAgent"
            || owner?.bundleIdentifier == "com.apple.TextInputSwitcher"
            || owner?.appName == "TextInputSwitcher"
    }

    var displayName: String {
        owner?.appName ?? ""
    }

    var fallbackSymbolName: String {
        if isInputMethodAgent {
            return "keyboard"
        }
        return SymbolFallback.name("menubar.rectangle", "app.dashed")
    }

    var appIcon: NSImage? {
        if isInputMethodAgent {
            return Self.currentInputSourceIcon()
        }
        guard let pid = owner?.pid,
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        guard Self.hasCustomBundleIcon(app: app) else { return nil }
        return app.icon
    }

    /// Reads the current keyboard input source's icon URL when available
    /// (e.g. third-party input methods); returns `nil` for system input sources
    /// that have no icon file so the caller renders the `keyboard` symbol.
    private static func currentInputSourceIcon() -> NSImage? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyIconImageURL),
              let url = Unmanaged<AnyObject>.fromOpaque(rawPtr).takeUnretainedValue() as? URL,
              url.isFileURL,
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    /// System agents such as `TextInputMenuAgent` have no icon in `Info.plist`,
    /// causing `NSRunningApplication.icon` to return a blank generic sheet.
    private static func hasCustomBundleIcon(app: NSRunningApplication) -> Bool {
        guard let bundleURL = app.bundleURL,
              let bundle = Bundle(url: bundleURL),
              let info = bundle.infoDictionary else { return false }
        if let iconFile = info["CFBundleIconFile"] as? String, !iconFile.isEmpty {
            return true
        }
        if let iconName = info["CFBundleIconName"] as? String, !iconName.isEmpty {
            return true
        }
        let assetsCar = bundleURL.appendingPathComponent("Contents/Resources/Assets.car")
        return FileManager.default.fileExists(atPath: assetsCar.path)
    }

    static func == (lhs: MenuBarTrayItem, rhs: MenuBarTrayItem) -> Bool {
        lhs.windowID == rhs.windowID
            && lhs.frame == rhs.frame
            && lhs.owner == rhs.owner
            && lhs.snapshot?.generation == rhs.snapshot?.generation
    }
}

/// A captured image of a menu bar item.
struct MenuBarItemSnapshot {
    let image: NSImage
    let isMonochrome: Bool
    let generation: UInt64
}

enum MenuBarTrayPhase: Equatable {
    case inactive
    case collapsed
    case arranging
    case blockedOwnIconHidden
}

struct MenuBarTrayPermissions: Equatable {
    var screenRecording: Bool
    var accessibility: Bool

    static let granted = MenuBarTrayPermissions(screenRecording: true, accessibility: true)
}

enum MenuBarTrayClick: Sendable {
    case left
    case right
}
