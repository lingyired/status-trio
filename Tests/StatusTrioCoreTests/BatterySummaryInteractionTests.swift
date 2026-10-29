import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BatterySummaryInteractionTests: XCTestCase {
    func testTitleBlankAreaAndChevronOpenDetailsWhileGearOnlyOpensSettings() throws {
        let suite = "BatterySummaryInteractionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let status = BatteryStatus(rawPercentage: 85, isPresent: true, isCharging: false,
            isLowPowerMode: false, isConnectedToPower: true)
        var detailOpens = 0
        var settingsOpens = 0
        let view = BatteryStatusView(
            state: PanelPresentationMapper.battery(status, localization: localization),
            onOpenBatteryDetails: { detailOpens += 1 },
            onOpenBatterySettings: { settingsOpens += 1 }
        )
        .padding(14)
        .frame(width: 330, height: 70)
        .environmentObject(localization)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 70)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Targets derive from the 330pt panel, 14pt padding,
        // 24pt trailing actions and 10pt gaps, independent of SF Symbol ink.
        // Mouse actions do not require keyboard focus or focusable AppKit proxies.
        for (index, target) in [("title", 88.0), ("blank", 215.0), ("chevron", 270.0)].enumerated() {
            let (name, x) = target
            let point = NSPoint(x: x, y: 35)
            try click(at: hosting.convert(point, to: nil), in: window)
            XCTAssertEqual(detailOpens, index + 1, "\(name) must open details exactly once")
            XCTAssertEqual(settingsOpens, 0, "\(name) must not open settings")
        }
        let gearPoint = NSPoint(x: 304, y: 35)
        try click(at: hosting.convert(gearPoint, to: nil), in: window)
        XCTAssertEqual(settingsOpens, 1)
        XCTAssertEqual(detailOpens, 3)
    }

    private func click(at point: NSPoint, in window: NSWindow) throws {
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }
        // AppKit controls may track until mouse-up inside mouseDown. Queue the
        // matching up event first so this in-process test never waits for input.
        let down = try event(.leftMouseDown)
        let up = try event(.leftMouseUp)
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date().addingTimeInterval(0.01),
                                  inMode: .eventTracking, dequeue: true) {
            window.sendEvent(up)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}
