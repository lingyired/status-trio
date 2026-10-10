import Foundation

/// What a paired device is, as finely as the sources let the app tell.
///
/// The class a device declares is its manufacturer's claim about the product,
/// not an observation of what it does. Those two disagree in practice: a
/// Logitech keyboard reports `Mouse` in `device_minorType` while the system
/// enumerates the Generic Desktop keyboard usage for it, which is the interface
/// macOS actually loads a keyboard driver for. So this is the *declared* class
/// and stays it: `BluetoothInputIconClassifier` decides only the glyph the row
/// draws, without changing this class.
enum BluetoothDeviceKind: Equatable, Sendable {
    case computer(ComputerForm)
    case mobile(MobileForm)
    /// Audio stays one case on purpose. Its glyph resolves through
    /// `AudioOutputDeviceIcon`, which already tells AirPods, Beats and HomePod
    /// apart by product ID and name, so splitting the class here would only
    /// duplicate that table and give the two surfaces a chance to drift.
    case audio
    case peripheral(PeripheralForm)
    case imaging(ImagingForm)
    case toy
    case health
    case unknown
}

enum ComputerForm: Equatable, Sendable {
    case laptop
    case desktop
    /// A computer the report did not describe further.
    case unclassified
}

enum MobileForm: Equatable, Sendable {
    case phone
    case tablet
    case watch
}

enum PeripheralForm: Equatable, Sendable {
    case keyboard
    case mouse
    case trackpad
    case gamepad
    /// An input device the class wording did not narrow down — a remote
    /// control, a card reader, a barcode scanner.
    case unclassified
}

enum ImagingForm: Equatable, Sendable {
    case printer
    case scanner
    case camera
    case display
    case unclassified
}

extension BluetoothDeviceKind {
    /// Whether the device is an audio device. The summary row and the device
    /// list both order AirPods first, and both ask this to find them.
    var isAudio: Bool {
        if case .audio = self { return true }
        return false
    }

    /// Whether disconnecting the device could cut the user off from their own
    /// input, which is the one action the row confirms before sending it.
    ///
    /// A peripheral the wording did not narrow down counts too. Confirming a
    /// remote control or a card reader costs one tap, while failing to confirm
    /// the keyboard the user is typing on costs them their session.
    var isPeripheral: Bool {
        if case .peripheral = self { return true }
        return false
    }

    /// Whether a HID usage the system enumerates for this device may refine how
    /// its row is drawn.
    ///
    /// Only the two classes the report cannot be trusted on. An audio device, a
    /// phone or a computer never declares a peripheral class, so a stray HID
    /// interface on one of them must not move it into the input family. This
    /// gates the display classification; it no longer changes `kind` itself.
    var acceptsHIDRefinement: Bool {
        switch self {
        case .peripheral, .unknown: true
        case .computer, .mobile, .audio, .imaging, .toy, .health: false
        }
    }
}

/// Classifies a device from the class wording the report carries.
///
/// Two rules the previous table broke, and each one hid a whole family of
/// devices behind the generic glyph:
///
/// - A minor slot never carries a major name. macOS reports `Laptop` or
///   `Smartphone` in `device_minorType`, never `Computer` or `Phone`, so
///   matching major names against that key classified nothing and every phone
///   and every Mac fell through.
/// - macOS 26 reports no `device_majorType` at all, so the major table can only
///   be a fallback for the reports that do carry one — it is never the second
///   half of the common path.
///
/// Matching is exact on normalized wording first, then a substring pass ordered
/// so `headphone`, `earphone` and `microphone` are all tested before `phone`.
/// The wording is manufacturer-supplied and Apple has spelled the same class
/// differently across releases, so an exact-only table would keep falling back
/// to the generic glyph.
enum BluetoothDeviceKindResolver {
    /// The keys that carry a class, most precise first. macOS 26 reports only
    /// `device_minorType`; `device_minorClassOfDevice_string` is the name the
    /// same wording arrives under in other reports.
    static let minorTypeKeys = ["device_minorType", "device_minorClassOfDevice_string"]
    static let majorTypeKeys = ["device_majorType", "device_majorClassOfDevice_string"]

    static func kind(properties: [String: Any]) -> BluetoothDeviceKind {
        kind(
            minorTypes: wordings(in: properties, keys: minorTypeKeys),
            majorTypes: wordings(in: properties, keys: majorTypeKeys)
        )
    }

    /// The minor wordings decide first because they are the precise ones; the
    /// major wordings are only consulted when none of them classified.
    static func kind(minorTypes: [String], majorTypes: [String]) -> BluetoothDeviceKind {
        for wording in minorTypes {
            if let kind = minorKind(wording) { return kind }
        }
        for wording in majorTypes {
            if let kind = majorKind(wording) { return kind }
        }
        return .unknown
    }

    private static func wordings(in properties: [String: Any], keys: [String]) -> [String] {
        keys.compactMap { properties[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Lowercased with everything that is not a letter or a digit removed, so
    /// `Smart Phone`, `Loudspeaker` and `Record Player`-style punctuation all
    /// land on one key.
    private static func normalized(_ wording: String) -> String {
        wording.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func minorKind(_ wording: String) -> BluetoothDeviceKind? {
        let key = normalized(wording)
        if let kind = minorKindsByWording[key] { return kind }
        return containsRules.first { key.contains($0.token) }?.kind
    }

    private static func majorKind(_ wording: String) -> BluetoothDeviceKind? {
        let key = normalized(wording)
        if let kind = majorKindsByWording[key] { return kind }
        return majorContainsRules.first { key.contains($0.token) }?.kind
    }

    /// The precise table. Keys are the minor class names of the Bluetooth
    /// assigned numbers, plus the spellings macOS uses for them.
    private static let minorKindsByWording: [String: BluetoothDeviceKind] = [
        // Computer
        "laptop": .computer(.laptop),
        "notebook": .computer(.laptop),
        "laptopcomputer": .computer(.laptop),
        "desktop": .computer(.desktop),
        "desktopcomputer": .computer(.desktop),
        "desktopworkstation": .computer(.desktop),
        "workstation": .computer(.desktop),
        "server": .computer(.desktop),
        "serverclasscomputer": .computer(.desktop),
        "computer": .computer(.unclassified),
        "computeruncategorized": .computer(.unclassified),
        "handheldpc": .computer(.unclassified),
        "handheldpcpda": .computer(.unclassified),
        "pda": .computer(.unclassified),
        "palmsizedpc": .computer(.unclassified),
        "palmsizepcpda": .computer(.unclassified),
        "wearablecomputer": .computer(.unclassified),

        // Mobile
        "tablet": .mobile(.tablet),
        "tabletcomputer": .mobile(.tablet),
        "smartphone": .mobile(.phone),
        "cellphone": .mobile(.phone),
        "cellular": .mobile(.phone),
        "cellularphone": .mobile(.phone),
        "cordless": .mobile(.phone),
        "cordlessphone": .mobile(.phone),
        "wiredmodem": .mobile(.phone),
        "voicegateway": .mobile(.phone),
        "wiredmodemorvoicegateway": .mobile(.phone),
        "isdn": .mobile(.phone),
        "commonisdnaccess": .mobile(.phone),
        "phone": .mobile(.phone),
        "phoneuncategorized": .mobile(.phone),
        "watch": .mobile(.watch),
        "wristwatch": .mobile(.watch),

        // Audio / video
        "headphones": .audio,
        "headphone": .audio,
        "wearableheadset": .audio,
        "headset": .audio,
        "handsfree": .audio,
        "loudspeaker": .audio,
        "speaker": .audio,
        "hifi": .audio,
        "hifiaudio": .audio,
        "microphone": .audio,
        "portableaudio": .audio,
        "caraudio": .audio,
        "settopbox": .audio,
        "vcr": .audio,
        "videocamera": .audio,
        "camcorder": .audio,
        "videomonitor": .audio,
        "videodisplayandloudspeaker": .audio,
        "videoconferencing": .audio,
        "audio": .audio,
        "audiovideo": .audio,
        "audiovideounclassified": .audio,

        // Peripheral
        "keyboard": .peripheral(.keyboard),
        "keypad": .peripheral(.keyboard),
        "combinedkeyboardpointing": .peripheral(.keyboard),
        "keyboardpointingdevice": .peripheral(.keyboard),
        "mouse": .peripheral(.mouse),
        "pointingdevice": .peripheral(.mouse),
        "pointer": .peripheral(.mouse),
        "trackball": .peripheral(.mouse),
        "trackpad": .peripheral(.trackpad),
        "touchpad": .peripheral(.trackpad),
        "digitizertablet": .peripheral(.trackpad),
        "gamepad": .peripheral(.gamepad),
        "joystick": .peripheral(.gamepad),
        "gamecontroller": .peripheral(.gamepad),
        "controller": .peripheral(.gamepad),
        "remotecontrol": .peripheral(.unclassified),
        "sensingdevice": .peripheral(.unclassified),
        "cardreader": .peripheral(.unclassified),
        "digitalpen": .peripheral(.unclassified),
        "barcodescanner": .peripheral(.unclassified),
        "handheldbarcodescanner": .peripheral(.unclassified),
        "handheldgestureinputdevice": .peripheral(.unclassified),
        "peripheral": .peripheral(.unclassified),
        "peripheraluncategorized": .peripheral(.unclassified),
        "input": .peripheral(.unclassified),

        // Imaging
        "printer": .imaging(.printer),
        "scanner": .imaging(.scanner),
        "camera": .imaging(.camera),
        "display": .imaging(.display),
        "monitor": .imaging(.display),
        "projector": .imaging(.display),
        "imaging": .imaging(.unclassified),
        "imaginguncategorized": .imaging(.unclassified),

        // Toy
        "toy": .toy,
        "robot": .toy,
        "vehicle": .toy,
        "dollactionfigure": .toy,
        "game": .toy,
        "videogamingtoy": .toy,

        // Health
        "health": .health,
        "bloodpressure": .health,
        "bloodpressuremonitor": .health,
        "thermometer": .health,
        "scale": .health,
        "weighingscale": .health,
        "glucosemeter": .health,
        "pulseoximeter": .health,
        "pulserate": .health,
        "pulseratemonitor": .health,
        "heartrate": .health,
        "heartratemonitor": .health,
        "healthdatadisplay": .health,

        // Wording that names no device the app can draw
        "miscellaneous": .unknown,
        "uncategorized": .unknown,
        "unclassified": .unknown,
        "unknown": .unknown,
        "none": .unknown,
        "any": .unknown,
        "networkaccesspoint": .unknown,
        "lanaccesspoint": .unknown,
        "accesspoint": .unknown,
    ]

    /// The substring pass, in test order. Each token has to come after every
    /// longer word that contains it: `microphone` and `headphone` both contain
    /// `phone`, and a phone glyph on a headset would be the same class of bug
    /// as the mouse glyph on a keyboard.
    private static let containsRules: [(token: String, kind: BluetoothDeviceKind)] = [
        ("touchpad", .peripheral(.trackpad)),
        ("trackpad", .peripheral(.trackpad)),
        ("digitizer", .peripheral(.trackpad)),
        ("keyboard", .peripheral(.keyboard)),
        ("keypad", .peripheral(.keyboard)),
        ("gamepad", .peripheral(.gamepad)),
        ("gamecontroller", .peripheral(.gamepad)),
        ("joystick", .peripheral(.gamepad)),
        ("mouse", .peripheral(.mouse)),
        ("trackball", .peripheral(.mouse)),
        ("pointing", .peripheral(.mouse)),
        ("headphone", .audio),
        ("earphone", .audio),
        ("earbud", .audio),
        ("headset", .audio),
        ("speaker", .audio),
        ("microphone", .audio),
        ("hifi", .audio),
        ("tablet", .mobile(.tablet)),
        ("watch", .mobile(.watch)),
        ("laptop", .computer(.laptop)),
        ("notebook", .computer(.laptop)),
        ("desktop", .computer(.desktop)),
        ("workstation", .computer(.desktop)),
        ("server", .computer(.desktop)),
        ("smartphone", .mobile(.phone)),
        ("cellular", .mobile(.phone)),
        ("printer", .imaging(.printer)),
        ("scanner", .imaging(.scanner)),
        ("camera", .imaging(.camera)),
        ("projector", .imaging(.display)),
        ("monitor", .imaging(.display)),
        ("display", .imaging(.display)),
        ("robot", .toy),
        ("bloodpressure", .health),
        ("thermometer", .health),
        ("glucose", .health),
        ("heartrate", .health),
        ("pulse", .health),
        ("scale", .health),
        ("phone", .mobile(.phone)),
        ("computer", .computer(.unclassified)),
        ("audio", .audio),
        ("peripheral", .peripheral(.unclassified)),
        ("input", .peripheral(.unclassified)),
        ("imaging", .imaging(.unclassified)),
    ]

    /// The coarse table, for the reports that carry a major class and a minor
    /// the precise table did not recognize.
    private static let majorKindsByWording: [String: BluetoothDeviceKind] = [
        "computer": .computer(.unclassified),
        "phone": .mobile(.phone),
        "audio": .audio,
        "audiovideo": .audio,
        "peripheral": .peripheral(.unclassified),
        "input": .peripheral(.unclassified),
        "imaging": .imaging(.unclassified),
        "toy": .toy,
        "health": .health,
    ]

    /// `wearable` is deliberately absent. Its five minor classes are a watch, a
    /// pager, a jacket, a helmet and glasses, so guessing any one of them would
    /// put the wrong glyph on four devices out of five. A watch that names its
    /// minor class resolves through the precise table above.
    private static let majorContainsRules: [(token: String, kind: BluetoothDeviceKind)] = [
        ("computer", .computer(.unclassified)),
        ("phone", .mobile(.phone)),
        ("audio", .audio),
        ("peripheral", .peripheral(.unclassified)),
        ("input", .peripheral(.unclassified)),
        ("imaging", .imaging(.unclassified)),
        ("toy", .toy),
        ("health", .health),
    ]
}

/// Seeds each connected input device's display classification from the HID
/// interfaces the system enumerates for it.
///
/// The declared class stays authoritative on the device itself: this only sets
/// `inputIconClassification`, the glyph the row draws. A device that presents
/// both mouse and keyboard interfaces — or whose declared class conflicts with
/// what it enumerates — is left to draw the generic input glyph rather than a
/// definite but possibly wrong one.
enum BluetoothInputIconSeed {
    static func apply(
        to devices: [BluetoothDevice],
        hidUsages: [String: [BluetoothHIDUsage]]
    ) -> [BluetoothDevice] {
        devices.map { device in
            guard device.isConnected, device.kind.acceptsHIDRefinement else {
                return device
            }

            let capabilities = BluetoothHIDCapabilities(
                usages: hidUsages[BluetoothBatteryReader.normalizedAddress(device.id)] ?? []
            )
            let classification = BluetoothInputIconClassifier.classify(
                declared: device.kind,
                capabilities: capabilities
            )
            return device.replacingInputIconClassification(with: classification)
        }
    }
}
