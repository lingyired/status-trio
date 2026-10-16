import Foundation
import Testing
@testable import StatusTrioCore

/// The class table, driven by the wordings macOS and the Bluetooth assigned
/// numbers actually use.
///
/// The regression this pins: the previous table matched major-class names
/// (`Computer`, `Phone`) against `device_minorType`, which only ever carries a
/// minor name. Every phone and every Mac therefore classified as nothing and
/// drew the generic glyph, and macOS 26 reports no `device_majorType` to
/// rescue them.
struct BluetoothDeviceKindTests {
    @Test(arguments: [
        ("Laptop", BluetoothDeviceKind.computer(.laptop)),
        ("Desktop", .computer(.desktop)),
        ("Smartphone", .mobile(.phone)),
        ("Cellular", .mobile(.phone)),
        ("Tablet", .mobile(.tablet)),
        ("Wristwatch", .mobile(.watch)),
        ("Keyboard", .peripheral(.keyboard)),
        ("Mouse", .peripheral(.mouse)),
        ("Trackpad", .peripheral(.trackpad)),
        ("Gamepad", .peripheral(.gamepad)),
        ("Joystick", .peripheral(.gamepad)),
        ("Digitizer Tablet", .peripheral(.trackpad)),
        ("Remote Control", .peripheral(.unclassified)),
        ("Combined Keyboard Pointing", .peripheral(.unclassified)),
        ("Keyboard Pointing Device", .peripheral(.unclassified)),
        ("Headphones", .audio),
        ("Headset", .audio),
        ("Loudspeaker", .audio),
        ("Speaker", .audio),
        ("Microphone", .audio),
        ("Printer", .imaging(.printer)),
        ("Scanner", .imaging(.scanner)),
        ("Camera", .imaging(.camera)),
        ("Display", .imaging(.display)),
        ("Robot", .toy),
        ("Thermometer", .health),
        ("Blood Pressure Monitor", .health),
        ("Unknown", .unknown),
    ])
    func minorWordingsClassNameTheReportUses(wording: String, expected: BluetoothDeviceKind) {
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [wording], majorTypes: []) == expected)
    }

    /// The spellings that are not in the precise table still land, which is what
    /// keeps the generic glyph from coming back when Apple renames a class.
    @Test(arguments: [
        ("Smart Phone", BluetoothDeviceKind.mobile(.phone)),
        ("Notebook", .computer(.laptop)),
        ("Pointing Device", .peripheral(.mouse)),
        ("Wireless Keyboard", .peripheral(.keyboard)),
        ("Keyboard and Mouse", .peripheral(.unclassified)),
        ("Bluetooth Headphones", .audio),
        ("Portable Speaker", .audio),
        ("Home Printer", .imaging(.printer)),
        ("Wrist Watch", .mobile(.watch)),
    ])
    func substringMatchingCoversSpellingVariants(wording: String, expected: BluetoothDeviceKind) {
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [wording], majorTypes: []) == expected)
    }

    /// `phone` is a substring of `headphone`, `earphone` and `microphone`, so
    /// the substring pass has to test the longer words first. Getting this wrong
    /// puts a phone glyph on a headset — the same class of bug as the mouse
    /// glyph on a keyboard.
    @Test(arguments: ["Headphone", "Headphones", "Earphone", "Microphone", "Ear Buds"])
    func audioWordingsThatContainPhoneStayAudio(wording: String) {
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [wording], majorTypes: []) == .audio)
    }

    /// The major table is a fallback for the reports that carry one, which
    /// macOS 26 does not.
    @Test func theMajorTypeStillClassifiesWhenTheMinorTypeIsAbsent() {
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [], majorTypes: ["Peripheral"]) == .peripheral(.unclassified))
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [], majorTypes: ["Phone"]) == .mobile(.phone))
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [], majorTypes: ["Audio"]) == .audio)
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [], majorTypes: ["Imaging"]) == .imaging(.unclassified))
    }

    /// Never guessed. The five wearable minor classes are a watch, a pager, a
    /// jacket, a helmet and glasses, so any single choice would put the wrong
    /// glyph on four devices out of five — the previous table chose audio and
    /// drew headphones for all of them.
    @Test func aBareWearableMajorTypeIsNotGuessed() {
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [], majorTypes: ["Wearable"]) == .unknown)
    }

    /// A precise minor class outranks a coarse major one.
    @Test func theMinorTypeOutranksTheMajorType() {
        #expect(
            BluetoothDeviceKindResolver.kind(minorTypes: ["Keyboard"], majorTypes: ["Peripheral"])
                == .peripheral(.keyboard)
        )
    }

    /// The keys both the modern and the older report shapes carry.
    @Test func readsTheClassFromWhicheverKeyCarriesIt() {
        let modern: [String: Any] = ["device_minorType": "Keyboard"]
        let legacy: [String: Any] = ["device_minorClassOfDevice_string": "Trackpad"]
        let majorOnly: [String: Any] = ["device_majorClassOfDevice_string": "Peripheral"]

        #expect(BluetoothDeviceKindResolver.kind(properties: modern) == .peripheral(.keyboard))
        #expect(BluetoothDeviceKindResolver.kind(properties: legacy) == .peripheral(.trackpad))
        #expect(BluetoothDeviceKindResolver.kind(properties: majorOnly) == .peripheral(.unclassified))
    }

    /// A report that carries no class at all, and one that carries an empty
    /// string, are the same answer.
    @Test func anAbsentClassIsUnknown() {
        #expect(BluetoothDeviceKindResolver.kind(properties: [:]) == .unknown)
        #expect(BluetoothDeviceKindResolver.kind(properties: ["device_minorType": "  "]) == .unknown)
        #expect(BluetoothDeviceKindResolver.kind(minorTypes: [], majorTypes: []) == .unknown)
    }

    /// The confirmation gate follows the family, including the peripherals the
    /// wording did not narrow down.
    @Test func theInputGateFollowsTheFamily() {
        #expect(BluetoothDeviceKind.peripheral(.keyboard).isPeripheral)
        #expect(BluetoothDeviceKind.peripheral(.unclassified).isPeripheral)
        #expect(!BluetoothDeviceKind.audio.isPeripheral)
        #expect(!BluetoothDeviceKind.unknown.isPeripheral)

        #expect(BluetoothDeviceKind.audio.isAudio)
        #expect(!BluetoothDeviceKind.peripheral(.keyboard).isAudio)
    }

    /// Other presentation merging code can replace a kind without modifying
    /// the identity, connection state or battery lookup fields.
    @Test func replacingTheKindKeepsEveryOtherField() {
        let device = BluetoothDevice(
            id: "D3:6D:6C:40:A3:2E",
            name: "MX Keys",
            // Start with a mouse class so a presentation replacement is observable.
            kind: .peripheral(.mouse),
            isConnected: true,
            airPodsModel: nil,
            vendorID: 0x046D,
            productID: 0xB35B
        )

        let corrected = device.replacingKind(with: .peripheral(.keyboard))

        #expect(corrected.kind == .peripheral(.keyboard))
        #expect(corrected.id == device.id)
        #expect(corrected.name == device.name)
        #expect(corrected.isConnected)
        #expect(corrected.vendorID == 0x046D)
        #expect(corrected.productID == 0xB35B)
    }
}
