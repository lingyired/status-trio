import AppKit

/// The glyph each paired-device row draws.
///
/// The audio row resolves through the same mapping as the popup's output list,
/// so an AirPods draws the AirPods glyph macOS declares for its product ID
/// instead of the generic headphone one, and the two surfaces cannot drift.
///
/// Every other class has a list of candidates rather than one name, because a
/// symbol Apple adds in a later release must not render as a blank row on the
/// oldest macOS the app supports. The list is ordered most faithful first and
/// its last entry is old enough to ship everywhere. This is the same rule
/// `AudioOutputDeviceIcon.symbolCandidates` follows.
enum BluetoothDeviceRowIcon {
    static func symbolName(for device: BluetoothDevice) -> String {
        // A display classification, when one was resolved, outranks the class
        // the report declared: it is the one place the app records that a
        // keyboard/mouse composite cannot be told apart, and draws the generic
        // input glyph instead of guessing.
        if let classification = device.inputIconClassification {
            return symbolName(for: classification)
        }
        switch device.kind {
        case .audio:
            return AudioOutputDeviceIcon.symbolName(
                for: AudioDeviceIdentity(bluetooth: device.name, model: device.airPodsModel)
            )
        default:
            if device.kind == .mobile(.watch),
               BluetoothMobileDeviceModel.kind(forModel: device.appleMobileModel) == .mobile(.watch) {
                return availableSymbol(from: ["applewatch", "watch.analog", "clock"])
            }
            return symbolName(for: device.kind, name: device.name)
        }
    }

    /// Resolves the family only from a trusted model identifier. Nearby
    /// advertisement names are intentionally not used to guess product type.
    static func symbolName(forAppleModel model: String?) -> String {
        guard let kind = BluetoothMobileDeviceModel.kind(forModel: model) else {
            return genericSymbol
        }
        return symbolName(for: kind)
    }

    static func symbolName(for kind: BluetoothDeviceKind) -> String {
        symbolName(for: kind, name: "")
    }

    static func symbolName(for kind: BluetoothDeviceKind, name: String) -> String {
        let candidates = candidateSymbols(for: kind, name: name)
        return availableSymbol(from: candidates)
    }

    /// The glyph for a resolved display classification. The definite forms
    /// reuse the class table so the two can never drift; `genericInput` draws
    /// the same non-committal radio as an unclassified device, which is the
    /// honest glyph for a device whose keyboard/mouse identity is unknown.
    static func symbolName(for classification: BluetoothInputIconClassification) -> String {
        availableSymbol(from: candidateSymbols(for: classification))
    }

    static func candidateSymbols(for classification: BluetoothInputIconClassification) -> [String] {
        switch classification {
        case .mouse: classCandidates(for: .peripheral(.mouse))
        case .keyboard: classCandidates(for: .peripheral(.keyboard))
        case .trackpad: classCandidates(for: .peripheral(.trackpad))
        case .gamepad: classCandidates(for: .peripheral(.gamepad))
        case .genericInput: [genericSymbol]
        }
    }

    private static func availableSymbol(from candidates: [String]) -> String {
        candidates.first {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        } ?? candidates.last ?? genericSymbol
    }

    /// What a device whose class the report did not describe draws.
    ///
    /// A radio glyph, not `questionmark.circle`. macOS reserves the question
    /// mark for a page the user has to fix, and an unreported class is not a
    /// fault — it is the ordinary state of a manufacturer that never filled the
    /// field in. Every comparable app draws a generic wireless glyph here, and
    /// the glyph now also covers the devices the previous table sent to the
    /// question mark by classifying nothing.
    static let genericSymbol = "dot.radiowaves.left.and.right"

    /// Kept apart from the availability check so the order is unit-tested on
    /// the strings, rather than on whichever symbols the machine running the
    /// tests happens to ship.
    static func candidateSymbols(for kind: BluetoothDeviceKind) -> [String] {
        candidateSymbols(for: kind, name: "")
    }

    static func candidateSymbols(for kind: BluetoothDeviceKind, name: String) -> [String] {
        namedCandidates(for: kind, name: name) ?? classCandidates(for: kind)
    }

    /// What the device's own name narrows the glyph to, ahead of its class's
    /// list.
    ///
    /// The Bluetooth class stops at the family — a Mac mini, an iMac and a Mac
    /// Pro all declare `Desktop`, and nothing in the class tells them apart —
    /// but Apple's products name themselves after the model, so the name can
    /// pick the model's glyph. The rule is bounded on purpose: it only runs
    /// inside the class the report already declared, so a mouse that happens to
    /// be named like a Mac can never be drawn as one, and the class list stays
    /// the fallback when the name names no model the app has a glyph for.
    private static func namedCandidates(for kind: BluetoothDeviceKind, name: String) -> [String]? {
        // Lowercased with the punctuation dropped, so `Mac mini`, `MacMini` and
        // `Mac mini (书桌)` land on one key.
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch kind {
        case .computer(.desktop), .computer(.unclassified):
            if key.contains("macmini") { return ["macmini", "desktopcomputer"] }
            if key.contains("macstudio") { return ["macstudio", "desktopcomputer"] }
            if key.contains("macbook") { return ["laptopcomputer"] }
            // An iMac and a Mac Pro have no symbol of their own; the desktop
            // glyph is already the honest one for both.
            return nil
        case .mobile(.phone):
            return key.contains("iphone") ? ["iphone", "smartphone"] : nil
        default:
            return nil
        }
    }

    private static func classCandidates(for kind: BluetoothDeviceKind) -> [String] {
        switch kind {
        case .computer(.laptop):
            ["laptopcomputer"]
        // A report that names no form leaves the two equally likely, so the
        // generic machine glyph is the honest one; a report that says `Laptop`
        // or `Desktop` is drawn exactly.
        case .computer(.desktop), .computer(.unclassified):
            ["desktopcomputer"]
        case .mobile(.phone):
            ["smartphone", "iphone"]
        case .mobile(.tablet):
            // Landscape, so the tablet is told apart from the phone at a glance
            // in a column that draws both: portrait, an iPad and an iPhone are
            // nearly the same rounded rectangle. The portrait glyph stays as the
            // fallback because it is the older of the two.
            ["ipad.landscape", "ipad"]
        // A wristwatch class covers every brand, so the generic watch leads and
        // the Apple one is only the fallback.
        case .mobile(.watch):
            ["watch.analog", "applewatch", "clock"]
        // Reached only when the row draws this class without a device to
        // resolve it by; `symbolName(for:)` sends every real audio device
        // through `AudioOutputDeviceIcon` first.
        case .audio:
            ["headphones"]
        case .peripheral(.keyboard):
            ["keyboard"]
        case .peripheral(.mouse):
            ["computermouse"]
        case .peripheral(.trackpad):
            ["rectangle.and.hand.point.up.left"]
        case .peripheral(.gamepad):
            ["gamecontroller"]
        case .peripheral(.unclassified):
            [genericSymbol]
        case .imaging(.printer):
            ["printer"]
        case .imaging(.scanner):
            ["scanner"]
        case .imaging(.camera):
            ["camera"]
        case .imaging(.display):
            ["tv"]
        case .imaging(.unclassified):
            [genericSymbol]
        case .toy:
            ["gamecontroller"]
        case .health:
            ["heart.text.square", "waveform.path.ecg"]
        case .unknown:
            [genericSymbol]
        }
    }
}
