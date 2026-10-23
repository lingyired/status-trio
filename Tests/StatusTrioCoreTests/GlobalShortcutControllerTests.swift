import Carbon
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class GlobalShortcutControllerTests: XCTestCase {
    func testStartIsIdempotentAndDeliversTheStoredShortcut() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }

        fixture.controller.start()
        fixture.controller.start()

        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
        XCTAssertEqual(fixture.backend.registrationAttempts.count, 1)

        fixture.backend.deliverLiveAction()
        XCTAssertEqual(fixture.activationCount, 1)
    }

    func testStartWithoutABindingStaysIdle() throws {
        let fixture = try makeFixture(storedShortcut: nil)
        defer { fixture.clear() }

        fixture.controller.start()
        fixture.controller.beginRecording()
        fixture.controller.endRecording()

        XCTAssertTrue(fixture.backend.registrationAttempts.isEmpty)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
        XCTAssertNil(fixture.controller.feedback)
    }

    func testSelectingTheExistingShortcutIsANoOp() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let generation = fixture.backend.registrationAttempts.count

        XCTAssertTrue(fixture.controller.setShortcut(shortcutA))
        fixture.controller.endRecording()

        XCTAssertEqual(fixture.backend.registrationAttempts.count, generation)
        XCTAssertEqual(fixture.backend.unregisteredTokens.count, 0)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
    }

    func testSuccessfulRebindReplacesTheOldTokenAndPersistsOnlyAfterRegistration() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let oldToken = try XCTUnwrap(fixture.backend.liveTokens.first)
        fixture.backend.onRegister = { _ in
            XCTAssertEqual(fixture.settings.statusPanelShortcut, self.shortcutA)
        }

        XCTAssertTrue(fixture.controller.setShortcut(shortcutB))

        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutB)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutB])
        XCTAssertEqual(fixture.backend.unregisteredTokens, [oldToken])

        fixture.backend.deliverAction(for: oldToken)
        XCTAssertEqual(fixture.activationCount, 0)
        fixture.backend.deliverLiveAction()
        XCTAssertEqual(fixture.activationCount, 1)
    }

    func testFailedRebindKeepsTheStoredAndLiveShortcut() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let oldToken = try XCTUnwrap(fixture.backend.liveTokens.first)
        fixture.backend.failures = [.conflict]

        XCTAssertFalse(fixture.controller.setShortcut(shortcutB))

        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
        XCTAssertEqual(fixture.controller.feedback, .conflict)
        XCTAssertEqual(fixture.backend.unregisteredTokens, [])

        fixture.backend.deliverAction(for: oldToken)
        XCTAssertEqual(fixture.activationCount, 1)
    }

    func testKnownInputMethodConflictIsRejectedBeforeRegistration() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        fixture.controller.beginRecording()
        let optionSpace = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: 49,
                modifiers: UInt32(optionKey)
            )
        )

        XCTAssertFalse(fixture.controller.setShortcut(optionSpace))

        XCTAssertEqual(fixture.controller.feedback, .inputMethodConflict)
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertEqual(fixture.backend.registrationAttempts.count, 1)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
    }

    func testStoredInputMethodConflictIsRejectedAtStartup() throws {
        let optionSpace = try XCTUnwrap(
            StatusPanelShortcut(
                keyCode: 49,
                modifiers: UInt32(optionKey)
            )
        )
        let fixture = try makeFixture(storedShortcut: optionSpace)
        defer { fixture.clear() }

        fixture.controller.start()

        XCTAssertEqual(fixture.controller.feedback, .inputMethodConflict)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, optionSpace)
        XCTAssertTrue(fixture.backend.registrationAttempts.isEmpty)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
    }

    func testRecordingSuspendsAndStaleActionsCannotOpenThePanel() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let oldToken = try XCTUnwrap(fixture.backend.liveTokens.first)

        fixture.controller.beginRecording()
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)

        fixture.backend.deliverAction(for: oldToken)
        XCTAssertEqual(fixture.activationCount, 0)

        fixture.backend.failures = [.other]
        XCTAssertFalse(fixture.controller.setShortcut(shortcutB))
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertEqual(fixture.backend.liveShortcuts, [])
        XCTAssertEqual(fixture.controller.feedback, .registrationFailed)

        fixture.backend.deliverAction(for: oldToken)
        XCTAssertEqual(fixture.activationCount, 0)

        fixture.controller.endRecording()
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
        fixture.backend.deliverLiveAction()
        XCTAssertEqual(fixture.activationCount, 1)
    }

    func testFailedStartupIsObservableAndCanBeRetriedByReassigning() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.backend.failures = [.conflict]

        fixture.controller.start()

        XCTAssertEqual(fixture.controller.feedback, .conflict)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)

        XCTAssertTrue(fixture.controller.setShortcut(shortcutA))
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
        XCTAssertNil(fixture.controller.feedback)
    }

    func testRestorationFailureIsReportedHonestly() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        fixture.controller.beginRecording()
        fixture.backend.failures = [.conflict, .other]

        XCTAssertFalse(fixture.controller.setShortcut(shortcutB))

        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
        XCTAssertEqual(fixture.controller.feedback, .conflict)

        fixture.controller.endRecording()
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
        XCTAssertEqual(fixture.controller.feedback, .restorationFailed)
    }

    func testClearAlwaysPersistsNilAndRemovesTheRegistration() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()

        fixture.controller.clearShortcut()
        fixture.controller.clearShortcut()

        XCTAssertNil(fixture.settings.statusPanelShortcut)
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
        XCTAssertNil(fixture.controller.feedback)
    }

    func testStopAndRestartInvalidateOldActionsAndReinstallOnce() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        let firstToken = try XCTUnwrap(fixture.backend.liveTokens.first)

        fixture.controller.stop()
        fixture.controller.stop()
        XCTAssertTrue(fixture.backend.liveShortcuts.isEmpty)
        XCTAssertEqual(fixture.backend.stopCount, 2)

        fixture.controller.start()
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
        XCTAssertEqual(fixture.backend.registrationAttempts.count, 2)

        fixture.backend.deliverAction(for: firstToken)
        XCTAssertEqual(fixture.activationCount, 0)
        fixture.backend.deliverLiveAction()
        XCTAssertEqual(fixture.activationCount, 1)
    }

    func testCancelRecordingRestoresTheStoredShortcutWithoutChangingIt() throws {
        let fixture = try makeFixture(storedShortcut: shortcutA)
        defer { fixture.clear() }
        fixture.controller.start()
        fixture.controller.beginRecording()
        fixture.controller.reportInvalidShortcut()
        XCTAssertEqual(fixture.controller.feedback, .invalidCombination)

        fixture.controller.cancelRecording()

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertNil(fixture.controller.feedback)
        XCTAssertEqual(fixture.settings.statusPanelShortcut, shortcutA)
        XCTAssertEqual(fixture.backend.liveShortcuts, [shortcutA])
    }

    private var shortcutA: StatusPanelShortcut {
        StatusPanelShortcut(keyCode: 0, modifiers: UInt32(cmdKey))!
    }

    private var shortcutB: StatusPanelShortcut {
        StatusPanelShortcut(keyCode: 1, modifiers: UInt32(controlKey))!
    }

    private func makeFixture(storedShortcut: StatusPanelShortcut?) throws -> Fixture {
        let suiteName = "GlobalShortcutControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.statusPanelShortcut = storedShortcut
        let backend = FakeGlobalShortcutBackend()
        let activationCounter = ActivationCounter()
        let controller = GlobalShortcutController(
            settings: settings,
            backend: backend,
            action: { activationCounter.count += 1 }
        )
        return Fixture(
            defaults: defaults,
            suiteName: suiteName,
            settings: settings,
            backend: backend,
            controller: controller,
            activationCounter: activationCounter
        )
    }
}

@MainActor
private struct Fixture {
    let defaults: UserDefaults
    let suiteName: String
    let settings: SettingsStore
    let backend: FakeGlobalShortcutBackend
    let controller: GlobalShortcutController
    let activationCounter: ActivationCounter

    var activationCount: Int {
        activationCounter.count
    }

    func clear() {
        controller.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class ActivationCounter {
    var count = 0
}

@MainActor
private final class FakeGlobalShortcutBackend: GlobalShortcutRegistering {
    private struct Registration {
        let shortcut: StatusPanelShortcut
        let action: @MainActor () -> Void
    }

    private var registrations: [UUID: Registration] = [:]
    private var actionHistory: [UUID: @MainActor () -> Void] = [:]

    var failures: [GlobalShortcutRegistrationFailure] = []
    var onRegister: ((StatusPanelShortcut) -> Void)?
    private(set) var registrationAttempts: [StatusPanelShortcut] = []
    private(set) var unregisteredTokens: [UUID] = []
    private(set) var stopCount = 0

    var liveTokens: [UUID] {
        Array(registrations.keys)
    }

    var liveShortcuts: [StatusPanelShortcut] {
        registrations.values.map(\.shortcut)
    }

    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID {
        registrationAttempts.append(shortcut)
        onRegister?(shortcut)
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        let token = UUID()
        registrations[token] = Registration(shortcut: shortcut, action: action)
        actionHistory[token] = action
        return token
    }

    func unregister(_ token: UUID) {
        unregisteredTokens.append(token)
        registrations.removeValue(forKey: token)
    }

    func stop() {
        stopCount += 1
        registrations.removeAll()
    }

    func deliverLiveAction() {
        guard let action = registrations.values.first?.action else {
            XCTFail("Expected a live registration")
            return
        }
        action()
    }

    func deliverAction(for token: UUID) {
        guard let action = actionHistory[token] else {
            XCTFail("Expected a retained callback for \(token)")
            return
        }
        action()
    }
}
