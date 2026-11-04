import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
private final class ViewportSchedule {
    private var callbacks: [StatusPanelLayoutUpdateScheduler.Operation] = []

    func schedule(_ operation: @escaping StatusPanelLayoutUpdateScheduler.Operation) {
        callbacks.append(operation)
    }

    func drain() {
        while !callbacks.isEmpty { callbacks.removeFirst()() }
    }
}

@MainActor
private final class ViewportProbe {
    private(set) var value = CGRect.zero
    private(set) var writes: [CGRect] = []

    var binding: Binding<CGRect> {
        Binding(get: { self.value }, set: { value in
            self.value = value
            self.writes.append(value)
        })
    }

    func clearWrites() { writes = [] }
}

@MainActor
struct BluetoothListViewportBridgeTests {
    @Test func reportsOnlyTheClippedViewportAfterLeavingLayout() {
        let (scrollView, bridge) = fixture()
        let probe = ViewportProbe()
        let (coordinator, manual) = coordinator(probe)
        defer { coordinator.detach() }

        coordinator.bind(to: bridge)
        #expect(probe.writes.isEmpty)
        manual.drain()

        #expect(probe.value == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(probe.value.height < bridge.bounds.height)
        #expect(scrollView.documentView === bridge)
    }

    @Test func scrollingCoalescesToTheLatestVisibleRows() {
        let (scrollView, bridge) = fixture()
        let probe = ViewportProbe()
        let (coordinator, manual) = coordinator(probe)
        defer { coordinator.detach() }
        coordinator.bind(to: bridge)
        manual.drain()
        probe.clearWrites()

        scrollView.contentView.bounds.origin.y = 150
        for _ in 0..<100 { coordinator.noteBoundsChanged() }
        #expect(probe.writes.isEmpty)
        manual.drain()

        #expect(probe.writes == [CGRect(x: 0, y: 150, width: 200, height: 100)])
    }

    @Test func detachedTreeCancelsPendingReportsAndMayReattach() {
        let (scrollView, bridge) = fixture()
        let probe = ViewportProbe()
        let (coordinator, manual) = coordinator(probe)
        coordinator.bind(to: bridge)
        coordinator.detach()
        manual.drain()
        #expect(probe.writes.isEmpty)

        scrollView.contentView.bounds.origin.y = 200
        coordinator.noteBoundsChanged()
        manual.drain()
        #expect(probe.writes.isEmpty)

        coordinator.bind(to: bridge)
        manual.drain()
        #expect(probe.value == CGRect(x: 0, y: 200, width: 200, height: 100))
        coordinator.detach()
    }

    private func fixture() -> (NSScrollView, BluetoothListViewportBridge.BridgeView) {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let bridge = BluetoothListViewportBridge.BridgeView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 1000)
        )
        scrollView.documentView = bridge
        return (scrollView, bridge)
    }

    private func coordinator(
        _ probe: ViewportProbe
    ) -> (BluetoothListViewportBridge.Coordinator, ViewportSchedule) {
        let manual = ViewportSchedule()
        let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
        return (BluetoothListViewportBridge.Coordinator(viewport: probe.binding, scheduler: scheduler), manual)
    }
}
