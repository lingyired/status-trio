import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
private final class ManualSchedule {
    private var callbacks: [StatusPanelLayoutUpdateScheduler.Operation] = []

    func schedule(_ operation: @escaping StatusPanelLayoutUpdateScheduler.Operation) {
        callbacks.append(operation)
    }

    func drain() {
        while !callbacks.isEmpty {
            callbacks.removeFirst()()
        }
    }
}

@MainActor
private final class BindingProbe {
    private(set) var writes: [CGFloat] = []
    private(set) var value: CGFloat = 0

    var binding: Binding<CGFloat> {
        Binding(
            get: { self.value },
            set: { newValue in
                self.value = newValue
                self.writes.append(newValue)
            }
        )
    }

    func clearWrites() {
        writes.removeAll()
    }
}

@MainActor
struct StatusPanelScrollBridgeTests {
    private func makeScrollView(documentHeight: CGFloat = 1000, viewport: CGFloat = 100) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: viewport))
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 200, height: documentHeight)
        )
        return scrollView
    }

    private func expectedOffset(of scrollView: NSScrollView, documentHeight: CGFloat = 1000) -> CGFloat {
        PanelScrollOffset.topOffset(
            documentHeight: documentHeight,
            viewportHeight: scrollView.contentView.bounds.height,
            clipOriginY: scrollView.contentView.bounds.origin.y,
            documentIsFlipped: scrollView.documentView?.isFlipped ?? false
        )
    }

    private func makeCoordinator(
        probe: BindingProbe
    ) -> (PanelScrollBridge.Coordinator, ManualSchedule) {
        let manual = ManualSchedule()
        let scheduler = StatusPanelLayoutUpdateScheduler { manual.schedule($0) }
        let coordinator = PanelScrollBridge.Coordinator(
            offset: probe.binding,
            scheduler: scheduler
        )
        return (coordinator, manual)
    }

    @Test func attachingDoesNotWriteTheBindingUntilTheNextTurn() {
        let scrollView = makeScrollView()
        scrollView.contentView.bounds.origin = NSPoint(x: 0, y: 200)
        let probe = BindingProbe()
        let (coordinator, manual) = makeCoordinator(probe: probe)

        coordinator.bind(to: scrollView)
        #expect(probe.writes.isEmpty, "publication must leave the layout pass first")

        manual.drain()
        #expect(probe.writes == [expectedOffset(of: scrollView)])
    }

    @Test func aBurstOfBoundsChangesPublishesOnlyTheLatestOffset() {
        let scrollView = makeScrollView()
        let probe = BindingProbe()
        let (coordinator, manual) = makeCoordinator(probe: probe)
        coordinator.bind(to: scrollView)
        manual.drain()
        probe.clearWrites()

        scrollView.contentView.bounds.origin = NSPoint(x: 0, y: 300)
        for _ in 0..<100 {
            coordinator.noteBoundsChanged()
        }
        #expect(probe.writes.isEmpty, "bounds changes must not publish during the event")
        manual.drain()

        #expect(probe.writes == [expectedOffset(of: scrollView)])
    }

    @Test func detachCancelsAPendingPublication() {
        let scrollView = makeScrollView()
        let probe = BindingProbe()
        let (coordinator, manual) = makeCoordinator(probe: probe)
        coordinator.bind(to: scrollView)
        manual.drain()
        probe.clearWrites()

        scrollView.contentView.bounds.origin = NSPoint(x: 0, y: 400)
        coordinator.noteBoundsChanged()
        coordinator.detach()
        manual.drain()

        #expect(probe.writes.isEmpty, "a detached coordinator must not write the old binding")
    }

    @Test func rebindingAfterDetachPublishesAgain() {
        let first = makeScrollView()
        let second = makeScrollView(documentHeight: 1200)
        let probe = BindingProbe()
        let (coordinator, manual) = makeCoordinator(probe: probe)
        coordinator.bind(to: first)
        manual.drain()
        coordinator.detach()
        manual.drain()
        probe.clearWrites()

        second.contentView.bounds.origin = NSPoint(x: 0, y: 100)
        coordinator.bind(to: second)
        manual.drain()

        #expect(probe.writes == [expectedOffset(of: second, documentHeight: 1200)])
    }

    @Test func updatingTheBindingRedirectsPendingWrites() {
        let scrollView = makeScrollView()
        let first = BindingProbe()
        let second = BindingProbe()
        let (coordinator, manual) = makeCoordinator(probe: first)
        coordinator.bind(to: scrollView)
        manual.drain()
        first.clearWrites()

        scrollView.contentView.bounds.origin = NSPoint(x: 0, y: 300)
        coordinator.noteBoundsChanged()
        coordinator.updateBinding(second.binding)
        manual.drain()

        #expect(first.writes.isEmpty, "the replaced binding must not receive a stale write")
        #expect(second.writes == [expectedOffset(of: scrollView)])
    }

    @Test func aSubPointChangeDoesNotPublish() {
        let scrollView = makeScrollView()
        let probe = BindingProbe()
        let (coordinator, manual) = makeCoordinator(probe: probe)
        coordinator.bind(to: scrollView)
        manual.drain()
        probe.clearWrites()

        scrollView.contentView.bounds.origin = NSPoint(x: 0, y: 0.25)
        coordinator.noteBoundsChanged()
        manual.drain()

        #expect(probe.writes.isEmpty, "a sub-point offset change must not redraw the indicator")
    }
}
