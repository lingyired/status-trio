import Foundation

/// One accessory battery reading from the system's power-management accessory
/// sources — the data macOS's own accessory battery UI is built from.
///
/// An accessory source describes a *part* of an accessory, not a device: a set
/// of earbuds publishes one entry per part that is currently reporting, each
/// carrying its own `Part Identifier`. A reading is therefore mapped back onto
/// the channel its part names, and a reading with no part can only ever supply
/// the device-wide level. That is what keeps one bud's charge from being shown
/// as the whole device's.
struct BluetoothAccessoryBatteryLevel: Equatable, Sendable {
    let name: String
    let vendorID: Int?
    let productID: Int?
    let part: BluetoothAccessoryPart?
    let percentage: Int
}
/// Which part of an accessory a power source describes.
enum BluetoothAccessoryPart: Equatable, Sendable {
    case left
    case right
    case caseLevel

    /// The `Part Identifier` wording the accessory sources use. Wording the app
    /// does not know maps to no part, so the reading stays device-wide instead of
    /// landing in the channel of a bud it may not describe.
    init?(identifier: String?) {
        switch (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left": self = .left
        case "right": self = .right
        case "case": self = .caseLevel
        default: return nil
        }
    }
}

protocol BluetoothAccessoryBatteryReading: AnyObject {
    /// `nil` means the accessory sources could not be read at all; an empty
    /// array means they were read and list no accessory carrying a level.
    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void)
}

enum BluetoothAccessoryBatteryReader {
    /// `pmset -g accps -xml` prints one property list per power source,
    /// concatenated with no separator, so the documents are split before each is
    /// decoded. A document that does not decode is dropped instead of failing the
    /// whole read: this source is a refinement, and one unreadable document must
    /// not cost the readings that can be read.
    static func parse(xml: String) -> [BluetoothAccessoryBatteryLevel] {
        documents(in: xml).compactMap(level(from:))
    }

    static func documents(in xml: String) -> [[String: Any]] {
        xml.components(separatedBy: "<?xml").compactMap { chunk in
            guard chunk.contains("<plist"),
                  let data = ("<?xml" + chunk).data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let document = plist as? [String: Any] else {
                return nil
            }
            return document
        }
    }

    private static func level(from document: [String: Any]) -> BluetoothAccessoryBatteryLevel? {
        // The Mac's own battery is a power source too, and it is not an
        // accessory: its type is what keeps it out of this list.
        guard document["Type"] as? String == "Accessory Source",
              let percentage = percentage(of: document) else {
            return nil
        }
        return BluetoothAccessoryBatteryLevel(
            name: (document["Name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            vendorID: document["Vendor ID"] as? Int,
            productID: document["Product ID"] as? Int,
            part: BluetoothAccessoryPart(identifier: document["Part Identifier"] as? String),
            percentage: percentage
        )
    }

    /// `Current Capacity` is the charge left and `Max Capacity` the full charge,
    /// both in the source's own units: the Mac's battery counts in mAh while an
    /// accessory counts in percent, and dividing is what makes one number out of
    /// the two shapes.
    private static func percentage(of document: [String: Any]) -> Int? {
        guard let current = document["Current Capacity"] as? Int else { return nil }
        let maximum = document["Max Capacity"] as? Int ?? 100
        guard maximum > 0, current >= 0 else { return nil }
        let value = Int((Double(current) / Double(maximum) * 100).rounded())
        guard (0...100).contains(value) else { return nil }
        return value
    }
}
