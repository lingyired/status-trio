import Foundation

/// The AirPods model macOS identifies from a Bluetooth device's product ID.
///
/// macOS declares its own accessory classes. Every `com.apple.airpods*` type in
/// `/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist` carries a
/// `public.bluetooth-vendor-product-id` tag written as
/// `<vendor decimal>:<product decimal>`, for example `76:8207` for
/// `com.apple.airpods-gen2`, which is AirPods (2nd generation). Apple's
/// Bluetooth vendor ID is 76, or `0x004C`.
///
/// Two public sources report that pair for a connected device:
///
/// - CoreAudio's `kAudioDevicePropertyModelUID`, as `<product hex> <vendor hex>`
///   — the connected AirPods (2nd generation), A2031/A2032, reports
///   `"200f 4c"`.
/// - `system_profiler SPBluetoothDataType`, as `device_productID` and
///   `device_vendorID` — `"0x200F"` and `"0x004C"` for the same device.
///
/// The product ID is what keeps an AirPods drawing its own glyph after a
/// rename, when the device name no longer contains "AirPods".
enum AirPodsModel: Equatable, Sendable {
    /// AirPods (1st and 2nd generation) share one glyph: macOS declares
    /// `airpods` for both, and SF Symbols ships no `airpods.gen2`.
    case airPods
    case airPodsGen3
    case airPodsGen4
    case airPodsGen5
    case airPodsPro
    case airPodsProGen1
    case airPodsProGen3
    case airPodsMax

    /// Apple's Bluetooth vendor ID, `0x004C`.
    static let appleVendorID = 0x004C

    /// The model a Bluetooth product ID names, or nil when the ID is not an
    /// AirPods, including an Apple product ID this table does not know.
    init?(productID: Int?, vendorID: Int? = nil) {
        guard let productID, productID > 0 else { return nil }
        if let vendorID, vendorID != Self.appleVendorID { return nil }
        guard let model = Self.modelsByProductID[productID] else { return nil }
        self = model
    }

    /// Parses the `<product hex> <vendor hex>` pair CoreAudio reports in
    /// `kAudioDevicePropertyModelUID` for a Bluetooth device. Built-in and USB
    /// hardware report a name instead ("Speaker", "Digital Mic"), which does
    /// not parse.
    init?(modelUID: String?) {
        let tokens = (modelUID ?? "").split(whereSeparator: \.isWhitespace)
        guard let product = tokens.first.flatMap({ BluetoothHexIdentifier.value(from: String($0)) }) else {
            return nil
        }
        let vendor = tokens.dropFirst().first.flatMap { BluetoothHexIdentifier.value(from: String($0)) }
        self.init(productID: product, vendorID: vendor)
    }

    /// Parses the `0x200F` / `0x004C` strings `system_profiler` reports. A
    /// missing vendor ID still identifies the model, because the product ID
    /// space belongs to the vendor that declares it.
    init?(productIDText: String?, vendorIDText: String? = nil) {
        self.init(
            productID: BluetoothHexIdentifier.value(from: productIDText),
            vendorID: BluetoothHexIdentifier.value(from: vendorIDText)
        )
    }

    /// The device class to draw, matching the class the name-based mapping
    /// already resolves for the same model.
    var kind: AudioOutputDeviceKind {
        switch self {
        case .airPods:
            .airPods
        case .airPodsGen3:
            .airPodsGen3
        case .airPodsGen4:
            .airPodsGen4
        case .airPodsGen5:
            .airPodsGen5
        case .airPodsPro:
            .airPodsPro
        case .airPodsProGen1:
            .airPodsProGen1
        case .airPodsProGen3:
            .airPodsProGen3
        case .airPodsMax:
            .airPodsMax
        }
    }

    /// The product IDs macOS declares for the AirPods family.
    ///
    /// The 1st and 2nd generation, 3rd generation, Pro, and Max rows are the
    /// `public.bluetooth-vendor-product-id` tags macOS 26 ships. The 4th
    /// Later rows are confirmed by the matching nested CoreTypes bundle, with
    /// an independent catalog cross-check recorded in
    /// `docs/superpowers/plans/2026-09-30-airpods-5-identification.md`.
    private static let modelsByProductID: [Int: AirPodsModel] = [
        0x2002: .airPods,      // AirPods (1st generation)
        0x200F: .airPods,      // AirPods (2nd generation), A2031/A2032
        0x2013: .airPodsGen3,  // AirPods (3rd generation)
        0x2019: .airPodsGen4,  // AirPods 4
        0x201B: .airPodsGen4,  // AirPods 4 with Active Noise Cancellation
        0x201C: .airPodsGen4,
        0x201E: .airPodsGen4,
        0x2020: .airPodsGen4,
        0x2030: .airPodsGen5,  // AirPods 5
        0x2036: .airPodsGen5,
        0x200E: .airPodsProGen1,
        0x2014: .airPodsPro,   // AirPods Pro (2nd generation)
        0x2024: .airPodsPro,   // AirPods Pro 2 USB-C
        0x2027: .airPodsProGen3,
        0x2028: .airPodsProGen3,
        0x200A: .airPodsMax,
        0x201F: .airPodsMax,   // AirPods Max USB-C
        0x202D: .airPodsMax    // AirPods Max (2nd generation)
    ]

    /// Reads one hexadecimal token, with or without the `0x` prefix the
    /// profiler uses. Anything that is not hexadecimal does not parse, which is
    /// what keeps a device name out of the table. The parse itself lives in
    /// `BluetoothHexIdentifier`, because the paired-device reader has to keep the
    /// same IDs on the device.
}
