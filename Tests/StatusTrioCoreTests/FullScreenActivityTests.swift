import CoreGraphics
import Foundation
import Testing
@testable import StatusTrioCore

struct FullScreenActivityTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let ownPID: pid_t = 4242
    private let otherPID: pid_t = 9001

    private func window(
        ownerPID: pid_t,
        name: String? = "SomeGame",
        layer: Int = 0,
        alpha: Double = 1,
        bounds: CGRect
    ) -> FullScreenWindowInfo {
        FullScreenWindowInfo(
            ownerPID: ownerPID,
            ownerName: name,
            layer: layer,
            alpha: alpha,
            bounds: bounds
        )
    }

    @Test
    func detectsAnotherAppCoveringTheWholeDisplay() {
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: otherPID, bounds: display)],
            displayBounds: [display],
            ownPID: ownPID,
            frontmostPID: otherPID
        )
        #expect(isActive)
    }

    @Test
    func ignoresFullScreenWindowWhenTheActiveAppIsSomethingElse() {
        let thirdPID: pid_t = 7777
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: otherPID, bounds: display)],
            displayBounds: [display],
            ownPID: ownPID,
            frontmostPID: thirdPID
        )
        #expect(!isActive)
    }

    @Test
    func ignoresOurOwnWindows() {
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: ownPID, bounds: display)],
            displayBounds: [display],
            ownPID: ownPID
        )
        #expect(!isActive)
    }

    @Test
    func ignoresMaximizedWindowThatLeavesRoomForTheMenuBar() {
        let maximized = CGRect(x: 0, y: 25, width: display.width, height: display.height - 25)
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: otherPID, bounds: maximized)],
            displayBounds: [display],
            ownPID: ownPID
        )
        #expect(!isActive)
    }

    @Test
    func ignoresSystemOverlayOwners() {
        for owner in ["Window Server", "Dock", "Control Center", "Notification Center"] {
            let isActive = FullScreenActivity.isActive(
                windows: [window(ownerPID: otherPID, name: owner, bounds: display)],
                displayBounds: [display],
                ownPID: ownPID
            )
            #expect(!isActive, "expected \(owner) to be ignored")
        }
    }

    @Test
    func ignoresNonZeroLayerAndTransparentWindows() {
        let floating = window(ownerPID: otherPID, layer: 3, bounds: display)
        let transparent = window(ownerPID: otherPID, alpha: 0, bounds: display)
        let isActive = FullScreenActivity.isActive(
            windows: [floating, transparent],
            displayBounds: [display],
            ownPID: ownPID
        )
        #expect(!isActive)
    }

    @Test
    func detectsFullScreenOnASecondaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: otherPID, bounds: secondary)],
            displayBounds: [primary, secondary],
            ownPID: ownPID
        )
        #expect(isActive)
    }

    @Test
    func ignoresWindowThatCoversOnlyPartOfTheDisplay() {
        let partial = CGRect(x: 0, y: 0, width: display.width, height: display.height / 2)
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: otherPID, bounds: partial)],
            displayBounds: [display],
            ownPID: ownPID
        )
        #expect(!isActive)
    }

    @Test
    func noDisplaysMeansNoFullScreen() {
        let isActive = FullScreenActivity.isActive(
            windows: [window(ownerPID: otherPID, bounds: display)],
            displayBounds: [],
            ownPID: ownPID
        )
        #expect(!isActive)
    }
}
