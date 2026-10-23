import AppKit
import Carbon
import XCTest
@testable import StatusTrioCore

@MainActor
final class ShortcutRecorderTests: XCTestCase {
    func testRecordingAValidCombinationAssignsItAndEndsRecording() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton(
            layoutLabelProvider: { shortcut in
                ShortcutKeyLabel.string(
                    for: shortcut,
                    layoutCharacterProvider: { _ in "K" }
                )
            },
            currentModifierFlagsProvider: { [] },
            capturesCurrentPhysicalModifiers: false
        )

        button.beginRecording()
        XCTAssertEqual(
            button.title,
            fixture.localization.string(.settingsShortcutRecording)
        )
        XCTAssertEqual(
            button.accessibilityLabel(),
            fixture.localization.string(.settingsShortcutRecording)
        )
        button.keyDown(with: keyEvent(
            keyCode: 0,
            flags: [.command, .shift, .capsLock],
            characters: "ф",
            isRepeat: false
        ))

        let expected = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: 0,
                modifiers: UInt32(cmdKey | shiftKey)
            )
        )
        XCTAssertEqual(fixture.settings.statusPanelShortcut, expected)
        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.backend.liveShortcuts, [expected])
        XCTAssertEqual(button.title, "⇧⌘K")
        XCTAssertEqual(
            button.accessibilityLabel(),
            fixture.localization.string(.settingsShortcutChange)
        )
    }

    func testInvalidCombinationStaysRecording() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton(
            currentModifierFlagsProvider: { [] },
            capturesCurrentPhysicalModifiers: false
        )
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: 0,
            flags: [],
            characters: "a",
            isRepeat: false
        ))

        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.feedback, .invalidCombination)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
    }

    func testModifierOnlyInputIsRejectedWithoutChangingTheStoredShortcut() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: 55,
            flags: [.command],
            characters: "",
            isRepeat: false
        ))

        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.feedback, .invalidCombination)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
    }

    func testRepeatedEventsAreConsumedWithoutCommitting() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: 1,
            flags: [.control],
            characters: "s",
            isRepeat: true
        ))

        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertNil(fixture.controller.feedback)
    }

    func testCurrentPhysicalModifiersRecoverAKeyEventRewrittenByTheInputMethod() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton(
            currentModifierFlagsProvider: { [.option] },
            capturesCurrentPhysicalModifiers: true
        )
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: UInt16(kVK_ANSI_V),
            flags: [],
            characters: "v",
            isRepeat: false
        ))

        let expected = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: UInt32(kVK_ANSI_V),
                modifiers: UInt32(optionKey)
            )
        )
        XCTAssertEqual(fixture.settings.statusPanelShortcut, expected)
        XCTAssertFalse(fixture.controller.isRecording)
    }

    func testKnownInputMethodConflictKeepsTheRecorderOpenWithFeedback() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton(
            currentModifierFlagsProvider: { [.option] },
            capturesCurrentPhysicalModifiers: true
        )
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: 49,
            flags: [.option],
            characters: " ",
            isRepeat: false
        ))

        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.feedback, .inputMethodConflict)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
    }

    func testCommandCombinationsArriveThroughPerformKeyEquivalent() throws {
        let fixture = try makeFixture(storedShortcut: nil)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        XCTAssertTrue(button.performKeyEquivalent(with: keyEvent(
            keyCode: 2,
            flags: [.command, .option],
            characters: "d",
            isRepeat: false
        )))

        XCTAssertEqual(
            fixture.settings.statusPanelShortcut?.modifiers,
            UInt32(cmdKey | optionKey)
        )
        XCTAssertFalse(fixture.controller.isRecording)
    }

    func testEscapeCancelsAndRestoresTheStoredShortcut() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: 53,
            flags: [],
            characters: "\u{1B}",
            isRepeat: false
        ))

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
    }

    func testDeleteClearsTheShortcutAndEndsRecording() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: 51,
            flags: [],
            characters: "\u{7F}",
            isRepeat: false
        ))

        XCTAssertNil(fixture.settings.statusPanelShortcut)
        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
    }

    func testWindowDidResignKeyEndsRecordingAndRestoresRegistration() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        button.handleWindowDidResignKey()

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
    }

    func testSelectedLayoutChangeRefreshesTheVisibleCombinationWithoutPolling() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let notifications = RecorderInputSourceNotifications()
        var layoutLabel = "A"
        let button = fixture.makeButton(
            layoutLabelProvider: { shortcut in
                ShortcutKeyLabel.string(
                    for: shortcut,
                    layoutCharacterProvider: { _ in layoutLabel }
                )
            },
            notificationObserver: notifications
        )
        let window = host(button)
        defer { window.close() }
        XCTAssertEqual(button.title, "⌘A")
        XCTAssertEqual(notifications.observedNames, [
            InputSourceNotifications.selectedSourceChanged
        ])

        layoutLabel = "B"
        notifications.postSelectedSourceChanged()

        XCTAssertEqual(button.title, "⌘B")
        button.endRecordingForRemoval()
        XCTAssertEqual(notifications.removedTokenCount, 1)
    }

    func testRemovingTheControlEndsRecordingAndRestoresRegistration() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()
        button.beginRecording()

        button.endRecordingForRemoval()

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
    }

    func testOrdinaryInputOutsideRecordingDoesNotChangeSettings() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton()

        button.keyDown(with: keyEvent(
            keyCode: 0,
            flags: [],
            characters: "a",
            isRepeat: false
        ))

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertNil(fixture.controller.feedback)
    }

    func testRecordingTheSameCombinationEndsTheSuspensionWithoutAReplacement() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let button = fixture.makeButton(
            currentModifierFlagsProvider: { [] },
            capturesCurrentPhysicalModifiers: false
        )
        button.beginRecording()

        button.keyDown(with: keyEvent(
            keyCode: UInt16(shortcutA.keyCode),
            flags: [.command],
            characters: "a",
            isRepeat: false
        ))

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
    }

    private var shortcutA: StatusPanelShortcut {
        StatusPanelShortcut(keyCode: 0, modifiers: UInt32(cmdKey))!
    }

    private func keyEvent(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        characters: String,
        isRepeat: Bool
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }

    private func makeFixture(storedShortcut: StatusPanelShortcut?) throws -> RecorderFixture {
        let suiteName = "ShortcutRecorderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.statusPanelShortcut = storedShortcut
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let backend = RecorderBackend()
        let controller = GlobalShortcutController(
            settings: settings,
            backend: backend,
            action: {}
        )
        return RecorderFixture(
            defaults: defaults,
            suiteName: suiteName,
            settings: settings,
            localization: localization,
            backend: backend,
            controller: controller
        )
    }
}

@MainActor
private struct RecorderFixture {
    let defaults: UserDefaults
    let suiteName: String
    let settings: SettingsStore
    let localization: Localization
    let backend: RecorderBackend
    let controller: GlobalShortcutController

    func makeButton(
        layoutLabelProvider: ((StatusPanelShortcut) -> String)? = nil,
        notificationObserver: (any InputSourceNotificationObserving)? = nil,
        currentModifierFlagsProvider: @escaping () -> NSEvent.ModifierFlags = { [] },
        capturesCurrentPhysicalModifiers: Bool = false
    ) -> ShortcutRecorderButton {
        ShortcutRecorderButton(
            settings: settings,
            controller: controller,
            localization: localization,
            layoutLabelProvider: layoutLabelProvider,
            inputSourceNotificationObserver: notificationObserver,
            currentModifierFlagsProvider: currentModifierFlagsProvider,
            capturesCurrentPhysicalModifiers: capturesCurrentPhysicalModifiers
        )
    }

    func clear() {
        controller.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private func host(_ button: ShortcutRecorderButton) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = contentView
    contentView.addSubview(button)
    return window
}

@MainActor
private final class RecorderInputSourceNotifications: InputSourceNotificationObserving {
    private var handlers: [Notification.Name: @MainActor () -> Void] = [:]
    private(set) var observedNames: [Notification.Name] = []
    private(set) var removedTokenCount = 0

    func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        observedNames.append(name)
        handlers[name] = handler
        return NSObject()
    }

    func remove(_ token: NSObjectProtocol) {
        removedTokenCount += 1
    }

    func postSelectedSourceChanged() {
        handlers[InputSourceNotifications.selectedSourceChanged]?()
    }
}

@MainActor
private final class RecorderBackend: GlobalShortcutRegistering {
    private struct Registration {
        let shortcut: StatusPanelShortcut
    }

    private var registrations: [UUID: Registration] = [:]

    var liveShortcuts: [StatusPanelShortcut] {
        registrations.values.map(\.shortcut)
    }

    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID {
        let token = UUID()
        registrations[token] = Registration(shortcut: shortcut)
        return token
    }

    func unregister(_ token: UUID) {
        registrations.removeValue(forKey: token)
    }

    func stop() {
        registrations.removeAll()
    }
}
