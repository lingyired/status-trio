import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

/// The glyph table, and the availability rule that keeps a symbol Apple added
/// in a later release from rendering as a blank row.
struct BluetoothDeviceRowIconTests {
    @Test(arguments: [
        (BluetoothDeviceKind.computer(.laptop), "laptopcomputer"),
        (.computer(.desktop), "desktopcomputer"),
        (.computer(.unclassified), "desktopcomputer"),
        (.mobile(.phone), "smartphone"),
        (.mobile(.tablet), "ipad.landscape"),
        (.mobile(.watch), "watch.analog"),
        (.peripheral(.keyboard), "keyboard"),
        (.peripheral(.mouse), "computermouse"),
        (.peripheral(.trackpad), "rectangle.and.hand.point.up.left"),
        (.peripheral(.gamepad), "gamecontroller"),
        (.imaging(.printer), "printer"),
        (.imaging(.scanner), "scanner"),
        (.imaging(.camera), "camera"),
        (.imaging(.display), "tv"),
        (.toy, "gamecontroller"),
        (.health, "heart.text.square"),
    ])
    func everyClassLeadsWithItsOwnGlyph(kind: BluetoothDeviceKind, expected: String) {
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: kind).first == expected)
    }

    /// Every class with no glyph of its own draws the same radio, not a
    /// question mark: an unreported class is not a fault.
    @Test func classesWithNoGlyphDrawTheGenericRadio() {
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: .unknown) == [BluetoothDeviceRowIcon.genericSymbol])
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: .peripheral(.unclassified)) == [BluetoothDeviceRowIcon.genericSymbol])
        #expect(BluetoothDeviceRowIcon.candidateSymbols(for: .imaging(.unclassified)) == [BluetoothDeviceRowIcon.genericSymbol])
        #expect(BluetoothDeviceRowIcon.symbolName(for: .unknown) == BluetoothDeviceRowIcon.genericSymbol)
    }

    /// A display classification outranks the declared class: a keyboard/mouse
    /// composite the app cannot name draws the generic radio, whatever its
    /// declared class says.
    @Test func aGenericInputClassificationDrawsTheGenericRadio() {
        #expect(BluetoothDeviceRowIcon.symbolName(for: .genericInput) == BluetoothDeviceRowIcon.genericSymbol)

        let composite = BluetoothDevice(
            id: "E3:3D:B6:E4:74:73",
            name: "HECATE G3M Pro",
            kind: .peripheral(.mouse),
            isConnected: true,
            inputIconClassification: .genericInput
        )
        #expect(BluetoothDeviceRowIcon.symbolName(for: composite) == BluetoothDeviceRowIcon.genericSymbol)

        let named = BluetoothDevice(
            id: "E3:3D:B6:E4:74:73",
            name: "HECATE G3M Pro",
            kind: .peripheral(.mouse),
            isConnected: true,
            inputIconClassification: .keyboard
        )
        #expect(BluetoothDeviceRowIcon.symbolName(for: named) == "keyboard")
    }

    @Test func aDeviceWithNoClassificationUsesItsClass() {
        let device = BluetoothDevice(
            id: "E3:3D:B6:E4:74:73",
            name: "M585/M590",
            kind: .peripheral(.mouse),
            isConnected: false
        )
        #expect(BluetoothDeviceRowIcon.symbolName(for: device) == "computermouse")
    }

    @Test func appleSelectionIconsRequireTrustedModelEvidence() {
        #expect(BluetoothDeviceRowIcon.symbolName(forAppleModel: "iPhone18,1") == "smartphone")
        #expect(BluetoothDeviceRowIcon.symbolName(forAppleModel: "iPad17,1") == "ipad.landscape")
        #expect(BluetoothDeviceRowIcon.symbolName(forAppleModel: "Watch12,1") == "watch.analog")
        #expect(BluetoothDeviceRowIcon.symbolName(forAppleModel: nil) == BluetoothDeviceRowIcon.genericSymbol)
        #expect(BluetoothDeviceRowIcon.symbolName(forAppleModel: "A phone named iPhone") == BluetoothDeviceRowIcon.genericSymbol)
    }

    /// The rule the audio icon table already follows: the running system
    /// resolves the list, so the last entry is what a macOS too old to ship any
    /// of the others falls back to and must never be blank.
    @Test func theLastCandidateIsTheOneEverySupportedMacHas() {
        let kinds: [BluetoothDeviceKind] = [
            .computer(.laptop), .computer(.desktop), .computer(.unclassified),
            .mobile(.phone), .mobile(.tablet), .mobile(.watch), .audio,
            .peripheral(.keyboard), .peripheral(.mouse), .peripheral(.trackpad),
            .peripheral(.gamepad), .peripheral(.unclassified),
            .imaging(.printer), .imaging(.scanner), .imaging(.camera),
            .imaging(.display), .imaging(.unclassified),
            .toy, .health, .unknown,
        ]

        for kind in kinds {
            guard let last = BluetoothDeviceRowIcon.candidateSymbols(for: kind).last else {
                Issue.record("\(kind) has no glyph candidates at all")
                continue
            }
            #expect(
                NSImage(systemSymbolName: last, accessibilityDescription: nil) != nil,
                "the fallback glyph \(last) for \(kind) does not exist on this macOS"
            )
        }
    }

    /// Whatever the running system ships, the row never resolves to a name it
    /// cannot draw.
    @Test func everyClassResolvesToASymbolThisMachineShips() {
        let kinds: [BluetoothDeviceKind] = [
            .computer(.laptop), .computer(.desktop), .computer(.unclassified),
            .mobile(.phone), .mobile(.tablet), .mobile(.watch), .audio,
            .peripheral(.keyboard), .peripheral(.mouse), .peripheral(.trackpad),
            .peripheral(.gamepad), .peripheral(.unclassified),
            .imaging(.printer), .imaging(.scanner), .imaging(.camera),
            .imaging(.display), .imaging(.unclassified),
            .toy, .health, .unknown,
        ]

        for kind in kinds {
            let name = BluetoothDeviceRowIcon.symbolName(for: kind)
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(kind) resolved to \(name), which this macOS does not ship"
            )
        }
    }

    /// The name narrows the glyph inside the class the report declared. The
    /// Bluetooth class stops at the family — every desktop Mac declares
    /// `Desktop` — and Apple's products name themselves after the model.
    @Test(arguments: [
        ("Mac mini", BluetoothDeviceKind.computer(.desktop), "macmini"),
        ("Mac mini (书桌)", BluetoothDeviceKind.computer(.desktop), "macmini"),
        ("MacMini", BluetoothDeviceKind.computer(.desktop), "macmini"),
        ("Mac Studio", BluetoothDeviceKind.computer(.desktop), "macstudio"),
        ("Mac Studio", BluetoothDeviceKind.computer(.unclassified), "macstudio"),
        ("MacBook Pro", BluetoothDeviceKind.computer(.desktop), "laptopcomputer"),
        ("iPhone 15 Pro", BluetoothDeviceKind.mobile(.phone), "iphone"),
    ])
    func appleNamesPickTheModelGlyph(name: String, kind: BluetoothDeviceKind, expected: String) {
        #expect(BluetoothDeviceRowIcon.symbolName(for: kind, name: name) == expected)
    }

    /// The refinement is bounded: a name runs only inside the class the report
    /// declared, and a name the app has no model glyph for changes nothing.
    @Test func theNameNeverCrossesTheDeclaredClass() {
        // A mouse that mentions a Mac stays a mouse.
        #expect(
            BluetoothDeviceRowIcon.symbolName(for: .peripheral(.mouse), name: "Mac mini Mouse")
                == "computermouse"
        )
        // A phone that is not an iPhone keeps the generic phone glyph.
        #expect(
            BluetoothDeviceRowIcon.symbolName(for: .mobile(.phone), name: "Pixel 9 Pro")
                == "smartphone"
        )
        // An iMac and a Mac Pro have no symbol of their own; the desktop glyph
        // is already the honest one for both.
        #expect(
            BluetoothDeviceRowIcon.symbolName(for: .computer(.desktop), name: "iMac")
                == "desktopcomputer"
        )
        #expect(
            BluetoothDeviceRowIcon.symbolName(for: .computer(.desktop), name: "Mac Pro")
                == "desktopcomputer"
        )
        // A laptop already drew the laptop glyph; the name changes nothing.
        #expect(
            BluetoothDeviceRowIcon.symbolName(for: .computer(.laptop), name: "MacBook Air")
                == "laptopcomputer"
        )
    }

    /// The named lists end on the same class fallback, so a macOS without the
    /// model glyph still resolves to a symbol it ships.
    @Test func everyNamedListEndsOnASymbolThisMachineShips() {
        let named: [(BluetoothDeviceKind, String)] = [
            (.computer(.desktop), "Mac mini"),
            (.computer(.desktop), "Mac Studio"),
            (.computer(.unclassified), "MacBook Pro"),
            (.mobile(.phone), "iPhone 15"),
        ]
        for (kind, name) in named {
            guard let last = BluetoothDeviceRowIcon.candidateSymbols(for: kind, name: name).last else {
                Issue.record("\(name) produced no candidates at all")
                continue
            }
            #expect(
                NSImage(systemSymbolName: last, accessibilityDescription: nil) != nil,
                "the fallback glyph \(last) for \(name) does not exist on this macOS"
            )
        }
    }

    /// An audio row still resolves through the output list's table, so an
    /// AirPods keeps the glyph macOS declares for its product ID.
    @Test func audioRowsResolveThroughTheOutputListTable() {
        let airPods = BluetoothDevice(
            id: "AC:90:85:C2:9C:1F",
            name: "机灵的耳机",
            kind: .audio,
            isConnected: true,
            airPodsModel: .airPods
        )

        #expect(BluetoothDeviceRowIcon.symbolName(for: airPods) == "airpods")
        // The class on its own has no device to resolve by, so it draws the
        // generic headphone glyph rather than nothing.
        #expect(BluetoothDeviceRowIcon.symbolName(for: .audio) != "")
    }
}
