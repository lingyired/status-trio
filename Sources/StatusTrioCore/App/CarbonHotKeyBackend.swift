import Carbon
import Foundation

private struct UncheckedSendableCarbonEvent: @unchecked Sendable {
    let event: EventRef
}

struct HotKeyActivationGate {
    private var pressedHotKeyIDs: Set<UInt32> = []

    mutating func shouldActivate(
        hotKeyID: UInt32,
        isRegistered: Bool = true
    ) -> Bool {
        guard isRegistered else { return false }
        return pressedHotKeyIDs.insert(hotKeyID).inserted
    }

    mutating func didRelease(hotKeyID: UInt32) {
        pressedHotKeyIDs.remove(hotKeyID)
    }

    mutating func reset() {
        pressedHotKeyIDs.removeAll()
    }
}

@MainActor
final class CarbonHotKeyBackend: GlobalShortcutRegistering {
    private struct Registration {
        let hotKeyID: UInt32
        let ref: EventHotKeyRef
        let action: @MainActor () -> Void
    }

    private static let signature: OSType = 0x5354_484B
    private static let handlerUPP: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }
        let backend = Unmanaged<CarbonHotKeyBackend>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let boxedEvent = UncheckedSendableCarbonEvent(event: event)
        return MainActor.assumeIsolated {
            backend.handleEvent(boxedEvent.event)
        }
    }

    private var registrations: [UUID: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 1
    private var activationGate = HotKeyActivationGate()

    func register(
        _ shortcut: StatusPanelShortcut,
        action: @escaping @MainActor () -> Void
    ) throws -> UUID {
        try installEventHandlerIfNeeded()

        let hotKeyID = nextHotKeyID
        nextHotKeyID &+= 1
        if nextHotKeyID == 0 {
            nextHotKeyID = 1
        }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyIDValue = EventHotKeyID(
            signature: Self.signature,
            id: hotKeyID
        )
        let result = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyIDValue,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        guard result == noErr, let hotKeyRef else {
            throw result == OSStatus(eventHotKeyExistsErr)
                ? GlobalShortcutRegistrationFailure.conflict
                : GlobalShortcutRegistrationFailure.other
        }

        let token = UUID()
        registrations[token] = Registration(
            hotKeyID: hotKeyID,
            ref: hotKeyRef,
            action: action
        )
        return token
    }

    func unregister(_ token: UUID) {
        guard let registration = registrations.removeValue(forKey: token) else {
            return
        }
        UnregisterEventHotKey(registration.ref)
        activationGate.didRelease(hotKeyID: registration.hotKeyID)
    }

    func stop() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
        activationGate.reset()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        var handlerRef: EventHandlerRef?
        let result = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                Self.handlerUPP,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
        }
        guard result == noErr, let handlerRef else {
            throw GlobalShortcutRegistrationFailure.other
        }
        eventHandlerRef = handlerRef
    }

    private func handleEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let parameterResult = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard parameterResult == noErr,
              hotKeyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let eventKind = GetEventKind(event)
        if eventKind == UInt32(kEventHotKeyReleased) {
            activationGate.didRelease(hotKeyID: hotKeyID.id)
            return noErr
        }
        guard eventKind == UInt32(kEventHotKeyPressed),
              let registration = registrations.values.first(
                  where: { $0.hotKeyID == hotKeyID.id }
              ),
              activationGate.shouldActivate(
                  hotKeyID: hotKeyID.id,
                  isRegistered: true
              ) else {
            return OSStatus(eventNotHandledErr)
        }
        registration.action()
        return noErr
    }
}
