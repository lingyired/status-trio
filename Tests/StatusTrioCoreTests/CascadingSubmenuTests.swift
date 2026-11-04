import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class CascadingSubmenuTests: XCTestCase {
    func testNewEntryClosesPreviousOwnerAndCloseIsIdempotent() {
        let coordinator = CascadingSubmenuCoordinator()
        let first = UUID(), second = UUID()
        var firstCloses = 0, secondCloses = 0
        coordinator.activate(owner: first) { firstCloses += 1 }
        coordinator.activate(owner: second) { secondCloses += 1 }
        XCTAssertEqual(firstCloses, 1)
        XCTAssertEqual(secondCloses, 0)
        coordinator.close(owner: first)
        XCTAssertEqual(secondCloses, 0, "a stale disappearing entry must not close its replacement")
        coordinator.close()
        coordinator.close()
        XCTAssertEqual(secondCloses, 1)
    }

    func testWholeParentCloseExposesReasonOnlyDuringBindingCleanup() {
        let coordinator = CascadingSubmenuCoordinator()
        var observed = false
        coordinator.activate(owner: UUID()) { observed = coordinator.isClosingParent }
        coordinator.closeForParent()
        XCTAssertTrue(observed)
        XCTAssertFalse(coordinator.isClosingParent)
        XCTAssertFalse(coordinator.hasOpenChild)
    }

    func testRepeatedOpenForSameOwnerDoesNotCloseIt() {
        let coordinator = CascadingSubmenuCoordinator()
        let owner = UUID()
        var closes = 0
        coordinator.activate(owner: owner) { closes += 1 }
        coordinator.activate(owner: owner) { closes += 1 }
        XCTAssertEqual(closes, 0)
        coordinator.close()
        XCTAssertEqual(closes, 1)
    }

    func testEnvironmentDefaultsDoNotCreateThirdLevelOrRequireCoordinator() {
        let environment = EnvironmentValues()
        XCTAssertNil(environment.cascadingSubmenuCoordinator)
        XCTAssertFalse(environment.isCascadingSubmenu)
    }

    func testStatusItemMouseDownIsExcludedFromLocalOutsideDismissal() {
        let panel = AnchoredStatusPanel()
        let statusFrame = NSRect(x: 1200, y: 850, width: 24, height: 24)
        panel.statusItemFrameForDismissal = { statusFrame }
        XCTAssertFalse(panel.shouldDismissForOutsideClick(at: NSPoint(x: 1212, y: 862)),
                       "the status item's later mouse-up owns the toggle")
        XCTAssertTrue(panel.shouldDismissForOutsideClick(at: NSPoint(x: 1100, y: 800)))
        panel.statusItemFrameForDismissal = { nil }
        XCTAssertTrue(panel.shouldDismissForOutsideClick(at: NSPoint(x: 1212, y: 862)))
    }

    func testPanelGroupOnlyOwnsItsOwnWindowWithoutAChild() {
        let panel = AnchoredStatusPanel()
        XCTAssertTrue(panel.ownsEventWindow(panel))
        XCTAssertFalse(panel.ownsEventWindow(nil))
        XCTAssertFalse(panel.ownsEventWindow(NSWindow()))
        XCTAssertFalse(panel.containsScreenPoint(.zero), "hidden windows are not part of the hit region")
    }
}

@MainActor
final class CascadingSubmenuNativeTests: VisibleUITestCase {
    private final class PresentationState: ObservableObject {
        @Published var first = false
        @Published var second = false
    }

    private struct Entries: View {
        @ObservedObject var state: PresentationState
        var body: some View {
            VStack {
                CascadingSubmenuButton(title: "First", isPresented: $state.first) {
                    LocalizedChild()
                }
                CascadingSubmenuButton(title: "Second", isPresented: $state.second) {
                    Text("Second child")
                }
            }
            .padding(14)
            .frame(width: 330)
        }
    }

    private struct LocalizedChild: View {
        @EnvironmentObject private var localization: Localization
        @Environment(\.isCascadingSubmenu) private var isChild
        @Environment(\.statusPanelManagesScrolling) private var managesScrolling
        var body: some View {
            Text(localization.string(.settingsTitle))
                .frame(height: isChild && managesScrolling ? 120 : 1)
        }
    }

    private struct RememberingEntry: View {
        @ObservedObject var state: PresentationState
        let coordinator: CascadingSubmenuCoordinator
        var body: some View {
            Button("Remembered detail") { state.first = true }
                .frame(width: 302, height: 32)
                .cascadingSubmenu(isPresented: Binding(
                    get: { state.first },
                    set: { value in
                        if value || !coordinator.isClosingParent { state.first = value }
                    }
                )) { Text("Remembered child") }
                .padding(14)
        }
    }

    func testParentMovementClosesChildAndParentTeardownPreservesRememberedBinding() async throws {
        let observation = NativeSubmenuInteractionObservation(label: "submenu-anchor-and-teardown")
        let state = PresentationState()
        let coordinator = CascadingSubmenuCoordinator()
        let parent = AnchoredStatusPanel()
        let anchorWindow = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 330, height: 50),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: anchorWindow.contentView!.bounds)
        anchorWindow.contentView!.addSubview(anchor)
        let content = RememberingEntry(state: state, coordinator: coordinator)
            .environmentObject(Localization())
            .environment(\.cascadingSubmenuCoordinator, coordinator)
        let host = StatusPanelHostingController(rootView: AnyView(content))
        parent.installContent(host, backgroundStyle: .solid)
        defer { parent.close(); anchorWindow.close(); observation.finish() }
        parent.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        try await Task.sleep(for: .milliseconds(100))
        state.first = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(coordinator.hasOpenChild)
        parent.setFrameOrigin(NSPoint(x: parent.frame.minX + 20, y: parent.frame.minY))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(coordinator.hasOpenChild, "a moved parent must not leave a child at the old anchor")
        XCTAssertFalse(state.first)
        state.first = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(coordinator.hasOpenChild)
        parent.close()
        XCTAssertTrue(state.first, "whole-group close preserves the remembered route")
        parent.contentViewController = nil
        host.rootView = AnyView(EmptyView())
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(state.first, "later representable dismantling must not reset an already-closed binding")
    }

    func testHoverWaitsCancelsOnExitAndKeepsChildOpenWhileCrossingToIt() async throws {
        let observation = NativeSubmenuInteractionObservation(label: "submenu-hover")
        let state = PresentationState()
        let coordinator = CascadingSubmenuCoordinator()
        let parent = AnchoredStatusPanel()
        let anchorWindow = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 330, height: 50),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: anchorWindow.contentView!.bounds)
        anchorWindow.contentView!.addSubview(anchor)
        let content = Entries(state: state)
            .environmentObject(Localization())
            .environment(\.cascadingSubmenuCoordinator, coordinator)
        parent.installContent(StatusPanelHostingController(rootView: content), backgroundStyle: .solid)
        defer { parent.close(); anchorWindow.close(); observation.finish() }
        parent.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        try await Task.sleep(for: .milliseconds(100))
        let trackingViews = allViews(in: try XCTUnwrap(parent.contentView)).filter { view in
            view.trackingAreas.contains { area in
                (area.owner as? NSView) === view
                    && area.options.contains([.mouseEnteredAndExited, .activeAlways, .inVisibleRect])
            }
        }
        XCTAssertEqual(trackingViews.count, 2, "the two menu entries each expose their native hover tracking area")
        let entry = try XCTUnwrap(trackingViews.first)
        let event = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: parent.windowNumber, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil
        ))
        entry.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(coordinator.hasOpenChild, "hover must not open before the 220ms threshold")
        entry.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertFalse(coordinator.hasOpenChild, "leaving cancels the pending open")
        entry.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(280))
        let child = try XCTUnwrap(parent.childWindows?.first as? AnchoredStatusPanel)
        XCTAssertTrue(child.isShown)
        entry.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(child.isShown, "crossing the gap toward the child must keep it open")
        XCTAssertTrue(coordinator.hasOpenChild)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(child.isShown, "leaving both entry and child must close after the crossing grace period")
        entry.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(280))
        let reopened = try XCTUnwrap(parent.childWindows?.first as? AnchoredStatusPanel)
        let childRegion = try XCTUnwrap(allViews(in: try XCTUnwrap(reopened.contentView)).first { view in
            view.trackingAreas.contains { area in
                (area.owner as? NSView) === view
                    && area.options.contains([.mouseEnteredAndExited, .activeAlways, .inVisibleRect])
            }
        })
        entry.mouseExited(with: event)
        childRegion.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(320))
        XCTAssertTrue(reopened.isShown, "entering the child cancels the pending close")
        childRegion.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(80))
        entry.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(320))
        XCTAssertTrue(reopened.isShown, "returning to the entry also cancels the pending close")
        entry.mouseExited(with: event)
        try await Task.sleep(for: .milliseconds(320))
        XCTAssertFalse(reopened.isShown)
        XCTAssertTrue(parent.isShown)
        XCTAssertFalse(state.first)
        XCTAssertFalse(state.second)
        parent.close()
        XCTAssertFalse(coordinator.hasOpenChild)
    }

    private func allViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allViews(in: $0) }
    }

    func testBindingsOpenOneNativeChildAndCloseTogetherWithRoot() async throws {
        let observation = NativeSubmenuInteractionObservation(label: "submenu-bindings")
        defer { observation.finish() }
        let state = PresentationState()
        let coordinator = CascadingSubmenuCoordinator()
        let parent = AnchoredStatusPanel()
        let anchorWindow = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 330, height: 50),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: anchorWindow.contentView!.bounds)
        anchorWindow.contentView!.addSubview(anchor)
        let content = Entries(state: state)
            .environmentObject(Localization())
            .environment(\.cascadingSubmenuCoordinator, coordinator)
        parent.installContent(StatusPanelHostingController(rootView: content), backgroundStyle: .solid)
        defer { parent.close(); anchorWindow.close() }
        parent.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        try await Task.sleep(for: .milliseconds(100))
        let originalFrame = parent.frame
        state.first = true
        try await Task.sleep(for: .milliseconds(100))
        let first = try XCTUnwrap(parent.childWindows?.first as? AnchoredStatusPanel)
        XCTAssertTrue(first.isShown)
        XCTAssertTrue(first.frame.minX >= parent.frame.maxX + StatusPanelPlacement.gap
            || first.frame.maxX <= parent.frame.minX - StatusPanelPlacement.gap)
        XCTAssertEqual(parent.frame, originalFrame, "opening a child must not resize or reposition the root")
        XCTAssertEqual((first.contentViewController as? StatusPanelContentViewController)?.backgroundStyle, .solid)
        XCTAssertGreaterThan(first.frame.height, 120, "child inherits localization and both child/scroll flags")
        state.second = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(state.first)
        XCTAssertTrue(state.second)
        XCTAssertEqual(parent.childWindows?.count, 1)
        XCTAssertFalse(first.isShown)
        // A local event in the status item's window is owned by its mouse-up
        // toggle; an ordinary outside point must still close the whole group.
        let statusWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 24, height: 24),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        statusWindow.isReleasedWhenClosed = false
        defer { statusWindow.close() }
        parent.statusItemFrameForDismissal = { statusWindow.frame }
        func outsideDown(at point: NSPoint) throws {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: statusWindow.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1
            ))
            NSApp.sendEvent(event)
        }
        try outsideDown(at: NSPoint(x: 12, y: 12))
        XCTAssertTrue(parent.isShown, "status mouse-down must wait for its own toggle")
        XCTAssertTrue(state.second)
        try outsideDown(at: NSPoint(x: 40, y: 12))
        XCTAssertFalse(parent.isShown, "the same local monitor must close a genuine outside click")
        XCTAssertFalse(state.second)
        XCTAssertFalse(coordinator.hasOpenChild)
        XCTAssertTrue(parent.childWindows?.isEmpty ?? true)
    }

    func testParentEscapeClosesChildFirstThenParentAndParentCloseClosesBoth() {
        let observation = NativeSubmenuInteractionObservation(label: "submenu-escape")
        defer { observation.finish() }
        let parent = AnchoredStatusPanel()
        let child = AnchoredStatusPanel()
        let coordinator = CascadingSubmenuCoordinator()
        let anchorWindow = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 330, height: 400),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: anchorWindow.contentView!.bounds)
        anchorWindow.contentView!.addSubview(anchor)
        defer { parent.close(); child.close(); anchorWindow.close() }
        parent.installContent(StatusPanelHostingController(rootView: Text("Parent").frame(width: 330, height: 200)),
                              backgroundStyle: .solid)
        child.installContent(StatusPanelHostingController(rootView: Text("Child").frame(width: 330, height: 200)),
                             backgroundStyle: .solid)
        parent.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        child.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX, alignsTop: true)
        parent.submenuCoordinator = coordinator
        parent.addChildWindow(child, ordered: .above)
        coordinator.activate(owner: UUID()) { child.close() }
        XCTAssertTrue(parent.ownsEventWindow(child))
        XCTAssertTrue(parent.containsScreenPoint(NSPoint(x: child.frame.midX, y: child.frame.midY)))
        parent.cancelOperation(nil)
        XCTAssertFalse(child.isShown)
        XCTAssertTrue(parent.isShown)
        parent.cancelOperation(nil)
        XCTAssertFalse(parent.isShown)
    }
}

/// Records the owned test process and its scoped window route. Endpoint pointer/
/// clipboard readings do not measure intervening user input or OS keyboard focus.
@MainActor
final class NativeSubmenuInteractionObservation {
    private let label: String
    private let start = ProcessInfo.processInfo.systemUptime
    private let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
    private let pointer = NSEvent.mouseLocation
    private let clipboard = NSPasteboard.general.changeCount
    private let keyWindow = NSApplication.shared.keyWindow?.windowNumber
    private var activations: [pid_t] = []
    private var workspaceChanges = 0
    private var observers: [NSObjectProtocol] = []

    init(label: String) {
        self.label = label
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { if let pid { self?.activations.append(pid) } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.workspaceChanges += 1 }
        })
    }

    func finish() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers = []
        print("SUBMENU_NATIVE_CONTEXT label=\(label) pid=\(ProcessInfo.processInfo.processIdentifier) "
            + "duration=\(ProcessInfo.processInfo.systemUptime - start) "
            + "foregroundBefore=\(String(describing: foreground)) foregroundAfter=\(String(describing: NSWorkspace.shared.frontmostApplication?.processIdentifier)) "
            + "activationPIDs=\(activations) spaceChanges=\(workspaceChanges) "
            + "pointerEndpointsEqual=\(pointer == NSEvent.mouseLocation) clipboardEndpointsEqual=\(clipboard == NSPasteboard.general.changeCount) "
            + "keyBefore=\(String(describing: keyWindow)) keyAfter=\(String(describing: NSApp.keyWindow?.windowNumber))")
    }
}
