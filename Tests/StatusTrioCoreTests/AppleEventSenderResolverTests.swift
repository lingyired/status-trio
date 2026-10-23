import AppKit
import Testing
@testable import StatusTrioCore

struct AppleEventSenderResolverTests {
    @Test func unsignedSenderPIDFromNativeReopenPreservesSettingsEntrypoint() throws {
        // Finder on macOS 27 sends spid as 'magn', despite the SDK's 'long'
        // annotation. Rejecting that valid integer loses the Settings route.
        for pid: UInt32 in [1, 55_710, 2_147_483_647] {
            var value = pid
            let data = withUnsafeBytes(of: &value) { Data($0) }
            let descriptor = try #require(NSAppleEventDescriptor(descriptorType: typeUInt32, data: data))
            let result = AppleEventSenderResolver.resolve(
                event: reopenEvent(),
                senderPIDDescriptor: { _ in descriptor },
                bundleIdentifierForPID: {
                    #expect($0 == pid_t(pid))
                    return "com.apple.finder"
                }
            )
            #expect(result.senderPID == pid_t(pid))
            #expect(result.sender == .finder)
            #expect(DockActivationAction.resolve(
                isReopenEvent: result.kind == .reopen,
                sender: result.sender,
                showsPersistentDockIcon: true
            ) == .openSettings)
        }
    }

    @Test func unsignedInvalidPIDNeverLooksUpAProcess() throws {
        for pid: UInt32 in [0, 2_147_483_648, 4_294_967_295] {
            var value = pid
            let data = withUnsafeBytes(of: &value) { Data($0) }
            let descriptor = try #require(NSAppleEventDescriptor(descriptorType: typeUInt32, data: data))
            let result = AppleEventSenderResolver.resolve(
                event: reopenEvent(),
                senderPIDDescriptor: { _ in descriptor },
                bundleIdentifierForPID: { _ in
                    Issue.record("zero or out-of-range unsigned PID must not be looked up")
                    return "com.apple.finder"
                }
            )
            #expect(result.senderPID == nil)
            #expect(result.sender == .unknown)
        }
    }

    @Test func senderPIDUsesExactBundleIdentities() {
        for (bundleID, expected) in [
            ("com.apple.dock", AppleEventSender.dock),
            ("com.apple.finder", .finder),
            ("com.apple.Spotlight", .spotlight),
            ("com.apple.apps.launcher", .launcher),
            ("com.apple.finder.impostor", .other),
            ("example.launcher", .other)
        ] {
            let event = reopenEvent()
            // Sender PID is a read-only system attribute, so inject its
            // descriptor rather than silently failing to set it on an event.
            let result = AppleEventSenderResolver.resolve(
                event: event,
                senderPIDDescriptor: { _ in NSAppleEventDescriptor(int32: 42) },
                bundleIdentifierForPID: { pid in
                    #expect(pid == 42)
                    return bundleID
                }
            )
            #expect(result.kind == .reopen)
            #expect(result.sender == expected)
            #expect(result.senderBundleIdentifier == bundleID)
        }
    }

    @Test func missingEventAndColdOrLoginLaunchNeverRouteToUI() {
        let events: [NSAppleEventDescriptor?] = [
            nil,
            NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEOpenApplication),
                targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            ),
            NSAppleEventDescriptor(
                eventClass: AEEventClass(kInternetEventClass),
                eventID: AEEventID(kAEReopenApplication),
                targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
        ]
        for event in events {
            let result = AppleEventSenderResolver.resolve(event: event, bundleIdentifierForPID: { _ in
                Issue.record("non-reopen events must not query a running process")
                return "com.apple.dock"
            })
            #expect(result.kind != .reopen)
            for placement in AppIconPlacement.allCases {
                #expect(DockActivationAction.resolve(
                    isReopenEvent: result.kind == .reopen,
                    sender: result.sender,
                    showsPersistentDockIcon: placement.showsDockIcon
                ) == .none)
            }
        }
    }

    @Test func missingPIDDoesNotMistakeTargetAddressForSender() {
        let event = reopenEvent()
        event.setAttribute(
            NSAppleEventDescriptor(processIdentifier: 42),
            forKeyword: AEKeyword(keyAddressAttr)
        )
        let result = AppleEventSenderResolver.resolve(event: event, bundleIdentifierForPID: { _ in
            Issue.record("the target address is not evidence of the sender PID")
            return "com.apple.finder"
        })
        #expect(result.kind == .reopen)
        #expect(result.sender == .unknown)
        #expect(result.senderBundleIdentifier == nil)
    }

    @Test func exitedProcessOrMissingBundleIdentityIsUnknown() {
        let event = reopenEvent()
        for bundleID: String? in [nil, ""] {
            let result = AppleEventSenderResolver.resolve(
                event: event,
                senderPIDDescriptor: { _ in NSAppleEventDescriptor(int32: 42) },
                bundleIdentifierForPID: { _ in bundleID }
            )
            #expect(result.sender == .unknown)
            #expect(result.senderBundleIdentifier == nil)
        }
    }

    @Test func invalidPIDDescriptorsFallBackWithoutProcessLookup() throws {
        let descriptors = [
            NSAppleEventDescriptor(string: "42"),
            NSAppleEventDescriptor(int32: 0),
            NSAppleEventDescriptor(int32: -1),
            try #require(NSAppleEventDescriptor(descriptorType: typeSInt32, data: Data([42]))),
            try #require(NSAppleEventDescriptor(descriptorType: typeSInt32, data: Data(repeating: 0, count: 8))),
            try #require(NSAppleEventDescriptor(descriptorType: typeUInt32, data: Data([42]))),
            try #require(NSAppleEventDescriptor(descriptorType: typeUInt32, data: Data(repeating: 0, count: 8)))
        ]
        for descriptor in descriptors {
            let event = reopenEvent()
            let result = AppleEventSenderResolver.resolve(
                event: event,
                senderPIDDescriptor: { _ in descriptor },
                bundleIdentifierForPID: { _ in
                    Issue.record("invalid PID must not be used to look up a process")
                    return "com.apple.finder"
                }
            )
            #expect(result.kind == .reopen)
            #expect(result.sender == .unknown)
        }
    }

    @Test func malformedTopLevelDescriptorDoesNothing() {
        let result = AppleEventSenderResolver.resolve(event: NSAppleEventDescriptor(string: "rapp"), bundleIdentifierForPID: { _ in
            Issue.record("a non-event descriptor must not resolve a sender")
            return "com.apple.dock"
        })
        #expect(result.kind == .other)
        #expect(result.sender == .unknown)
    }

    private func reopenEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }
}
