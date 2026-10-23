import AppKit

enum AppleEventSender: String, CaseIterable, Sendable {
    case dock
    case finder
    case spotlight
    case launcher
    case other
    case unknown

    init(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.apple.dock": self = .dock
        case "com.apple.finder": self = .finder
        case "com.apple.Spotlight": self = .spotlight
        case "com.apple.apps.launcher": self = .launcher
        case nil, "": self = .unknown
        default: self = .other
        }
    }
}

struct AppleEventActivation: Equatable {
    enum Kind: String {
        case reopen
        case other
        case missing
    }

    let kind: Kind
    let sender: AppleEventSender
    let senderPID: pid_t?
    let senderBundleIdentifier: String?
    let eventClass: AEEventClass?
    let eventID: AEEventID?
}

enum AppleEventSenderResolver {
    /// Read synchronously inside the delegate callback: the manager only owns
    /// this descriptor for the event currently being dispatched.
    @MainActor
    static func currentActivation() -> AppleEventActivation {
        resolve(event: NSAppleEventManager.shared().currentAppleEvent)
    }

    static func resolve(
        event: NSAppleEventDescriptor?,
        senderPIDDescriptor: (NSAppleEventDescriptor) -> NSAppleEventDescriptor? = {
            $0.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))
        },
        bundleIdentifierForPID: (pid_t) -> String? = {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
    ) -> AppleEventActivation {
        guard let event else {
            return AppleEventActivation(
                kind: .missing, sender: .unknown, senderPID: nil, senderBundleIdentifier: nil,
                eventClass: nil, eventID: nil
            )
        }
        guard event.descriptorType == typeAppleEvent else {
            return AppleEventActivation(
                kind: .other, sender: .unknown, senderPID: nil, senderBundleIdentifier: nil,
                eventClass: nil, eventID: nil
            )
        }
        let isReopen = event.eventClass == AEEventClass(kCoreEventClass)
            && event.eventID == AEEventID(kAEReopenApplication)
        var bundleID: String?
        var senderPID: pid_t?
        if isReopen,
           let descriptor = senderPIDDescriptor(event),
           descriptor.descriptorType == typeSInt32 || descriptor.descriptorType == typeUInt32 {
            let data = descriptor.data
            if data.count == MemoryLayout<UInt32>.size {
                // Native reopen events can supply 'magn' despite the SDK's
                // 'long' annotation. Both must fit a positive signed pid_t.
                var rawPID: UInt32 = 0
                // Copy into aligned storage instead of loading from Data's
                // potentially unaligned base address.
                _ = withUnsafeMutableBytes(of: &rawPID) { data.copyBytes(to: $0) }
                if let pid = pid_t(exactly: rawPID), pid > 0 {
                    senderPID = pid
                    bundleID = bundleIdentifierForPID(pid)
                }
            }
        }
        // keyAddressAttr describes the event's target, so even a valid kpid
        // address is not sufficient evidence of who sent the event.
        if bundleID?.isEmpty == true { bundleID = nil }
        return AppleEventActivation(
            kind: isReopen ? .reopen : .other,
            sender: AppleEventSender(bundleIdentifier: bundleID),
            senderPID: senderPID,
            senderBundleIdentifier: bundleID,
            eventClass: event.eventClass,
            eventID: event.eventID
        )
    }
}
