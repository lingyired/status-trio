import CoreBluetooth
import Foundation

/// Which advertisements the nearby battery scanner may open a GATT session with.
///
/// Two routes lead to a connection, and they exist for different devices.
///
/// A peripheral that lists the standard Battery Service (`180F`) in its
/// advertisement is asking to be read: the service is the whole reason to
/// connect, and a device that publishes it in the advertisement is one the
/// standard read can answer for. This is the route the scanner shipped with,
/// and it is the only thing a keyboard or a mouse ever offers.
///
/// An iPhone, an iPad or a Watch never advertises `180F`. Apple's mobile
/// devices broadcast their Continuity payload instead — manufacturer data whose
/// first byte is Apple's company identifier and whose third byte is the message
/// type — and the Battery Service only appears *after* the connection is up.
/// Reading an iOS device therefore starts with recognising that payload, which
/// is what makes the iPhone row work in AirBattery, whose parser this follows.
///
/// Advertisement recognition identifies Apple mobile candidates. A GATT session
/// is separately limited to a UUID whose row is currently visible in the panel.
enum BluetoothLEBatteryAdvertisement {
    /// Apple's Bluetooth SIG company identifier, first on the wire.
    static let appleCompanyIdentifier: UInt8 = 0x4C

    /// The Continuity message types an iOS device broadcasts while nearby.
    ///
    /// `0x10` is Nearby Info and `0x0C` is Handoff; Apple's phones and tablets
    /// send both. The byte after the company identifier is the message length,
    /// so the type is the third byte.
    static let continuityMessageTypes: Set<UInt8> = [0x10, 0x0C]

    /// The offset of the Continuity message type within the manufacturer data.
    private static let continuityMessageTypeOffset = 2

    /// Whether the advertisement offers the standard Battery Service, which is
    /// on its own enough to make a connection worth opening.
    ///
    /// The identifiers are compared case-insensitively because the two sides can
    /// disagree on case: a `CBUUID` built from a string keeps the string's own
    /// spelling, while one an advertisement carries is normalized.
    static func advertisesBatteryService(
        _ serviceUUIDs: [CBUUID]?,
        batteryService: CBUUID
    ) -> Bool {
        guard let serviceUUIDs else { return false }
        return serviceUUIDs.contains {
            $0.uuidString.caseInsensitiveCompare(batteryService.uuidString) == .orderedSame
        }
    }

    /// Whether the payload is an Apple mobile device announcing itself.
    ///
    /// The length is checked before the type byte is read, so a payload that is
    /// only the company identifier — or the identifier and a length, which is
    /// what AirPods send with their own message types — cannot be read past its
    /// end.
    static func isAppleMobileDevice(manufacturerData: Data?) -> Bool {
        guard let manufacturerData,
              manufacturerData.count > continuityMessageTypeOffset else {
            return false
        }
        // The indices are taken from `startIndex` rather than written as 0..2,
        // because a sliced `Data` keeps the offsets of the buffer it came from.
        return manufacturerData[manufacturerData.startIndex] == appleCompanyIdentifier
            && manufacturerData[manufacturerData.startIndex + 1] == 0x00
            && continuityMessageTypes.contains(
                manufacturerData[manufacturerData.startIndex + continuityMessageTypeOffset]
            )
    }

    /// Whether a discovered peripheral is worth a GATT session.
    ///
    /// `name` is the name the system already knows for the peripheral, taken
    /// from the advertisement when it carries one and from CoreBluetooth's cache
    /// otherwise. An absent or blank one is what a stranger's device looks like.
    ///
    /// `allowsAppleMobileDevices` follows the Apple-device master setting.
    /// An iOS device may ask to pair before it answers a read; matching the
    /// system's known names below does not bypass that device-owned prompt.
    /// The standard Battery Service route is unaffected: a keyboard or a mouse
    /// advertises `180F` and answers without asking for anything.
    ///
    /// `knownAppleMobileNames` is the system's own device list — the names
    /// `system_profiler SPBluetoothDataType` reports for this Mac. The
    /// Continuity route requires a match: every iPhone in radio range broadcasts
    /// the same payload, and the prompt one raises carries its own name
    /// ("iPhone"), so the payload alone would connect a stranger's phone and
    /// raise a prompt the user could neither answer nor identify (issue `#152`).
    /// Matching against the system list keeps the route on devices this Mac
    /// already has a record for, and needs no typing from the user.
    static func isCandidate(
        serviceUUIDs: [CBUUID]?,
        manufacturerData: Data?,
        name: String?,
        batteryService: CBUUID,
        allowsAppleMobileDevices: Bool,
        knownAppleMobileNames: Set<String>
    ) -> Bool {
        if advertisesBatteryService(serviceUUIDs, batteryService: batteryService) {
            return true
        }
        guard allowsAppleMobileDevices else { return false }
        guard isAppleMobileDevice(manufacturerData: manufacturerData) else { return false }
        return matchesKnownAppleMobileName(name, knownNames: knownAppleMobileNames)
    }

    /// Whether a discovered name matches one the system list carries.
    ///
    /// The comparison folds case and whitespace because the two sides come from
    /// different layers — the advertisement carries the phone's GAP name, the
    /// system list carries the record macOS stores — and they can disagree on
    /// nothing more than that. A blank name never matches anything: it is what a
    /// device this Mac has no record of looks like.
    static func matchesKnownAppleMobileName(_ name: String?, knownNames: Set<String>) -> Bool {
        let candidate = normalizedAppleMobileName(name)
        guard !candidate.isEmpty else { return false }
        return knownNames.contains { normalizedAppleMobileName($0) == candidate }
    }

    static func normalizedAppleMobileName(_ name: String?) -> String {
        (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
