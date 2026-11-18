import CoreGraphics
import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarTrayTests: XCTestCase {
    func testHiddenItemsFiltersToStatusLayerLeftOfSeparatorAndSortsLeftToRight() {
        let separatorFrame = CGRect(x: 900, y: 0, width: 18, height: 33)
        let windows: [MenuBarWindowInfo] = [
            MenuBarWindowInfo(
                windowID: 10,
                ownerPID: 677,
                ownerName: "Control Center",
                frame: CGRect(x: 840, y: 0, width: 38, height: 33),
                layer: MenuBarItemScanner.statusWindowLayer,
                isOnScreen: true
            ),
            MenuBarWindowInfo(
                windowID: 11,
                ownerPID: 677,
                ownerName: "Control Center",
                frame: CGRect(x: 780, y: 0, width: 38, height: 33),
                layer: MenuBarItemScanner.statusWindowLayer,
                isOnScreen: true
            ),
            // Separator itself (excluded by ID)
            MenuBarWindowInfo(
                windowID: 99,
                ownerPID: 677,
                ownerName: "Control Center",
                frame: separatorFrame,
                layer: MenuBarItemScanner.statusWindowLayer,
                isOnScreen: true
            ),
            // Visible item to the right of the separator
            MenuBarWindowInfo(
                windowID: 12,
                ownerPID: 677,
                ownerName: "Control Center",
                frame: CGRect(x: 940, y: 0, width: 38, height: 33),
                layer: MenuBarItemScanner.statusWindowLayer,
                isOnScreen: true
            ),
            // Non-status layer window
            MenuBarWindowInfo(
                windowID: 13,
                ownerPID: 438,
                ownerName: "Window Server",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 33),
                layer: 24,
                isOnScreen: true
            ),
            // Status panel window (too tall to be a menu bar icon)
            MenuBarWindowInfo(
                windowID: 14,
                ownerPID: 700,
                ownerName: "SomeApp",
                frame: CGRect(x: 700, y: 33, width: 320, height: 420),
                layer: MenuBarItemScanner.statusWindowLayer,
                isOnScreen: true
            )
        ]

        let hidden = MenuBarItemScanner.hiddenItems(
            in: windows,
            separatorFrame: separatorFrame,
            excludedWindowIDs: [99]
        )

        XCTAssertEqual(hidden.map(\.windowID), [11, 10])
    }

    func testOwnItemVisibleSideRequiresOwnItemToRightOfSeparator() {
        let separatorFrame = CGRect(x: 900, y: 0, width: 18, height: 33)
        let rightOfSeparator = CGRect(x: 960, y: 0, width: 38, height: 33)
        let leftOfSeparator = CGRect(x: 840, y: 0, width: 38, height: 33)

        XCTAssertTrue(
            MenuBarItemScanner.isOwnItemVisibleSide(
                ownFrame: rightOfSeparator,
                separatorFrame: separatorFrame
            )
        )
        XCTAssertFalse(
            MenuBarItemScanner.isOwnItemVisibleSide(
                ownFrame: leftOfSeparator,
                separatorFrame: separatorFrame
            )
        )
    }

    func testOwnerMatchingPairsClosestAXFrameWithinTolerance() {
        let window = MenuBarWindowInfo(
            windowID: 42,
            ownerPID: 677,
            ownerName: "Control Center",
            frame: CGRect(x: 812, y: 0, width: 38, height: 33),
            layer: MenuBarItemScanner.statusWindowLayer,
            isOnScreen: true
        )
        let owners = [
            MenuBarItemOwner(
                pid: 1001,
                elementIndex: 0,
                appName: "WeChat",
                bundleIdentifier: "com.tencent.xinWeChat",
                frame: CGRect(x: 760, y: 0, width: 38, height: 33)
            ),
            MenuBarItemOwner(
                pid: 1002,
                elementIndex: 0,
                appName: "ClashX",
                bundleIdentifier: "com.west2online.ClashX",
                frame: CGRect(x: 813, y: 0, width: 38, height: 33)
            )
        ]

        let matched = MenuBarItemScanner.match(window, owners: owners)
        XCTAssertEqual(matched?.appName, "ClashX")
        XCTAssertEqual(matched?.pid, 1002)
    }

    func testHiddenAXOwnersIncludesFoldedAndLeftOfSeparatorItems() {
        let separatorFrame = CGRect(x: 1100, y: 0, width: 18, height: 33)
        let ownFrame = CGRect(x: 1300, y: 0, width: 40, height: 33)
        let owners = [
            MenuBarItemOwner(
                pid: 2001,
                elementIndex: 0,
                appName: "FoldedApp",
                bundleIdentifier: "com.example.folded",
                frame: CGRect(x: -1000, y: 0, width: 28, height: 24)
            ),
            MenuBarItemOwner(
                pid: 2002,
                elementIndex: 0,
                appName: "LeftOfDividerApp",
                bundleIdentifier: "com.example.left",
                frame: CGRect(x: 1020, y: 0, width: 36, height: 33)
            ),
            MenuBarItemOwner(
                pid: 2003,
                elementIndex: 0,
                appName: "RightOfDividerApp",
                bundleIdentifier: "com.example.right",
                frame: CGRect(x: 1200, y: 0, width: 36, height: 33)
            )
        ]

        let hidden = MenuBarItemScanner.hiddenAXOwners(
            owners,
            separatorFrame: separatorFrame,
            ownFrame: ownFrame
        )
        XCTAssertEqual(hidden.map(\.appName), ["FoldedApp", "LeftOfDividerApp"])
    }

    func testMenuBarTraySectionIsOptInAndPlacedFirstInDefaultOrder() {
        let suiteName = "StatusTrioCoreTests.MenuBarTray.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.popupSectionOrder.first, .menuBarTray)
        XCTAssertFalse(store.enabledPopupSections.contains(.menuBarTray))

        store.setPopupSection(.menuBarTray, enabled: true)
        XCTAssertEqual(store.visiblePopupSections.first, .menuBarTray)
    }

    func testLiveRefreshAndAccessibilityAndCaptureDoNotCrash() async {
        let windows = MenuBarItemScanner.liveWindows()
        XCTAssertFalse(windows.isEmpty)
        let offscreenStatus = windows.filter {
            $0.layer == MenuBarItemScanner.statusWindowLayer
                && MenuBarItemScanner.itemHeightRange.contains($0.frame.height)
                && $0.frame.width <= MenuBarItemScanner.maximumItemWidth
                && $0.frame.minX < 0
        }
        print("Offscreen folded status items count: \(offscreenStatus.count)")
        var frames: [CGWindowID: CGRect] = [:]
        for w in offscreenStatus { frames[w.windowID] = w.frame }
        let captures = await MenuBarItemCapturer.capture(windows: frames, scale: 2)
        for (_, c) in captures {
            _ = MenuBarItemCapturer.analyze(c.image)
        }
    }

    func testNegativeOrZeroWindowNumberDoesNotTrapAndReturnsNil() {
        XCTAssertNil(MenuBarSeparatorController.validWindowID(fromWindowNumber: -1))
        XCTAssertNil(MenuBarSeparatorController.validWindowID(fromWindowNumber: 0))
        XCTAssertEqual(MenuBarSeparatorController.validWindowID(fromWindowNumber: 42), 42)
    }
}
