import AppKit
import CoreGraphics
import Foundation

/// Discovers menu bar items without adding any spacer to the system menu bar.
enum MenuBarItemScanner {
    static let statusWindowLayer = 25
    static let popUpMenuWindowLayer = 101

    static let itemHeightRange: ClosedRange<CGFloat> = 14...48
    static let maximumItemWidth: CGFloat = 600

    private static let ignoredSystemBundlePrefixes: [String] = [
        "com.apple."
    ]

    private static let ignoredOwnerNames: Set<String> = [
        "Window Server", "WindowManager", "MenuBarAgent", "Control Center",
        "控制中心", "SystemUIServer", "Spotlight", "Siri", "通知中心",
        "Notification Center", "程序坞", "Dock", "访达", "Finder",
        "AccessibilityVisualsAgent", "TextInputSwitcher", "TextInputMenuAgent",
        "nsattributedstringagent", "universalAccessAuthWarn", "loginwindow",
        "CoreServicesUIAgent", "UserNotificationCenter", "WiFiAgent"
    ]

    /// Known regular apps that host a persistent menu bar status item even when
    /// macOS 27's `MenuBarAgent` detaches collapsed items from `AXExtrasMenuBar`.
    static let defaultKnownMenuBarBundleIDs: Set<String> = [
        "com.tencent.xinWeChat",
        "com.tencent.WeWorkMac",
        "com.tencent.workbuddy.mac",
        "com.kimi.code.desktop",
        "com.xiaomi.hyperConnect",
        "cn.better365.iCopy",
        "app.cyan.tinycalx",
        "org.yuanli.utools",
        "io.github.clash-verge-rev.clash-verge-rev",
        "com.fortinet.forticlient.macos.vpn.tray",
        "com.termius-dmg.mac",
        "com.1password.1password",
        "com.raycast.macos",
        "com.snipaste.Snipaste",
        "com.macpaw.CleanMyMac4",
        "com.docker.docker"
    ]

    static func parse(_ dictionaries: [[String: Any]]) -> [MenuBarWindowInfo] {
        dictionaries.compactMap { dictionary in
            guard let number = dictionary[kCGWindowNumber as String] as? NSNumber,
                  let windowID = CGWindowID(exactly: number.int64Value),
                  windowID != kCGNullWindowID,
                  let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
                  let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }
            let pid = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            return MenuBarWindowInfo(
                windowID: windowID,
                ownerPID: pid,
                ownerName: dictionary[kCGWindowOwnerName as String] as? String ?? "",
                frame: bounds,
                layer: layer.intValue,
                isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            )
        }
    }

    static func liveWindows() -> [MenuBarWindowInfo] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return parse(raw)
    }

    static func liveWindow(id: CGWindowID) -> MenuBarWindowInfo? {
        let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []
        return parse(raw).first { $0.windowID == id }
    }

    static func isAnyMenuOpen(in windows: [MenuBarWindowInfo]) -> Bool {
        windows.contains { $0.layer == popUpMenuWindowLayer && $0.isOnScreen }
    }

    static func hiddenItems(
        in windows: [MenuBarWindowInfo],
        separatorFrame: CGRect,
        excludedWindowIDs: Set<CGWindowID>
    ) -> [MenuBarWindowInfo] {
        windows
            .filter { window in
                window.layer == statusWindowLayer
                    && !excludedWindowIDs.contains(window.windowID)
                    && itemHeightRange.contains(window.frame.height)
                    && window.frame.width > 0
                    && window.frame.width <= maximumItemWidth
                    && abs(window.frame.midY - separatorFrame.midY) <= 4
                    && window.frame.maxX <= separatorFrame.minX + 1
            }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    static func hiddenAXOwners(
        _ owners: [MenuBarItemOwner],
        separatorFrame: CGRect?,
        ownFrame: CGRect?
    ) -> [MenuBarItemOwner] {
        let cutoffX: CGFloat?
        if let sep = separatorFrame, sep.minX > 60, sep.width < 1000 {
            cutoffX = sep.minX + 2
        } else if let own = ownFrame, own.minX > 60 {
            cutoffX = own.minX + 2
        } else {
            cutoffX = nil
        }

        return owners
            .filter { owner in
                guard let cutoffX else { return true }
                return owner.frame.minX <= 0
                    || owner.frame.width <= 1
                    || owner.frame.maxX <= cutoffX
            }
            .sorted { lhs, rhs in
                if lhs.frame.minX != rhs.frame.minX {
                    return lhs.frame.minX < rhs.frame.minX
                }
                return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
            }
    }

    /// Discovers running third-party menu bar apps when macOS 27's official `«`
    /// overflow is collapsed (which detaches overflowed items from `AXExtrasMenuBar`).
    /// Combines `.accessory` menu bar apps with any running app whose bundle ID
    /// has been observed in `AXExtrasMenuBar` (`knownBundleIDs`).
    @MainActor
    static func fallbackMenuBarOwners(
        in windows: [MenuBarWindowInfo],
        knownBundleIDs: Set<String> = defaultKnownMenuBarBundleIDs,
        excludingOwnPID ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [MenuBarItemOwner] {
        var activeMenuBarPIDs: Set<pid_t> = []
        for window in windows where window.ownerPID != ownPID {
            guard !ignoredOwnerNames.contains(window.ownerName) else { continue }
            if window.layer == 0,
               window.frame.minX == 0,
               window.frame.minY == 0,
               itemHeightRange.contains(window.frame.height),
               window.frame.width >= 800 {
                activeMenuBarPIDs.insert(window.ownerPID)
            } else if window.layer == popUpMenuWindowLayer,
                      window.frame.minY >= 0,
                      window.frame.minY <= 60 {
                activeMenuBarPIDs.insert(window.ownerPID)
            }
        }

        var owners: [MenuBarItemOwner] = []
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != ownPID,
                  !app.isTerminated,
                  app.activationPolicy != .prohibited else { continue }
            let bundleID = app.bundleIdentifier ?? ""
            if ignoredSystemBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                continue
            }
            let bundlePath = app.bundleURL?.path ?? ""
            let isNestedHelper = bundlePath.components(separatedBy: ".app/").count > 2
            guard !isNestedHelper, bundlePath.hasSuffix(".app") else { continue }

            let name = app.localizedName ?? bundleID
            guard !name.isEmpty, !ignoredOwnerNames.contains(name) else { continue }

            let isAccessoryMenuBarApp = app.activationPolicy == .accessory && activeMenuBarPIDs.contains(pid)
            let isKnownMenuBarApp = !bundleID.isEmpty && knownBundleIDs.contains(bundleID)

            guard isAccessoryMenuBarApp || isKnownMenuBarApp else { continue }

            owners.append(MenuBarItemOwner(
                pid: pid,
                elementIndex: 0,
                appName: name,
                bundleIdentifier: app.bundleIdentifier,
                frame: CGRect(x: CGFloat(-1000 - owners.count * 32), y: 0, width: 28, height: 24)
            ))
        }

        return owners.sorted {
            $0.appName.localizedStandardCompare($1.appName) == .orderedAscending
        }
    }

    static func isOwnItemVisibleSide(ownFrame: CGRect, separatorFrame: CGRect) -> Bool {
        ownFrame.minX >= separatorFrame.maxX - 1
    }

    static func match(
        _ window: MenuBarWindowInfo,
        owners: [MenuBarItemOwner]
    ) -> MenuBarItemOwner? {
        owners
            .filter {
                abs($0.frame.minX - window.frame.minX) <= 3
                    && abs($0.frame.width - window.frame.width) <= 4
            }
            .min {
                abs($0.frame.minX - window.frame.minX) < abs($1.frame.minX - window.frame.minX)
            }
    }
}
