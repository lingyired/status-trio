import Foundation

/// One piece of a device's level as it is drawn.
///
/// The charging case is why this exists: it has no short word of its own, only
/// the hard-coded "Case" that none of the app's localizations carry, and the
/// row has no room for a word there anyway. Keeping a level as pieces rather
/// than as a finished string is what lets the row draw that one piece as a glyph
/// while every text-only surface — the summary that cannot draw, the
/// accessibility value, the tests that pin the wording — keeps reading the same
/// sentence it always did.
enum BluetoothBatterySegment: Equatable, Sendable {
    /// Characters drawn as they are.
    case text(String)
    /// A glyph drawn in place of a word.
    ///
    /// `label` is what the text-only rendering spells there instead, so the two
    /// forms of one level cannot drift apart.
    case symbol(name: String, label: String)
}
extension Array where Element == BluetoothBatterySegment {
    /// The pieces as one string, each glyph spelled out by its label.
    var plainText: String {
        map { segment in
            switch segment {
            case .text(let value): value
            case .symbol(_, let label): label
            }
        }
        .joined()
    }
}

struct BluetoothBatteryLevel: Equatable, Sendable {
    let deviceAddress: String
    let main: Int?
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    /// The level as the pieces a row draws, or `nil` when the report carries no
    /// channel for this device at all.
    ///
    /// The charging case is a glyph rather than the word "Case"; the percentage
    /// beside it stays text, because the word was the part with no room.
    var segments: [BluetoothBatterySegment]? {
        var pieces: [BluetoothBatterySegment] = []
        func append(_ piece: BluetoothBatterySegment) {
            if !pieces.isEmpty {
                pieces.append(.text(Self.separator))
            }
            pieces.append(piece)
        }

        if let main {
            append(.text("\(main)%"))
        }
        if let left {
            append(.text("L \(left)%"))
        }
        if let right {
            append(.text("R \(right)%"))
        }
        if let caseLevel {
            append(.symbol(name: Self.caseSymbolName, label: Self.caseTextLabel))
            pieces.append(.text(" \(caseLevel)%"))
        }
        return pieces.isEmpty ? nil : pieces
    }

    /// The same level as one sentence, glyphs spelled out by their labels. This
    /// is what the surfaces that cannot draw read, and what the wording tests
    /// pin.
    var summary: String? {
        segments?.plainText
    }

    /// The charging-case glyph.
    ///
    /// The outline form is deliberate: at the row's caption size the filled
    /// variant is a solid blob that reads as nothing in particular. The symbol
    /// ships from macOS 14 and the app's floor is 15, so the availability check
    /// the drawing side runs guards against a symbol table changing, not against
    /// the floor.
    static let caseSymbolName = "airpods.chargingcase"

    /// What the text-only rendering says where the row draws the glyph.
    static let caseTextLabel = "Case"

    /// Between two channels of one device.
    private static let separator = " · "
}

protocol BluetoothBatteryReading: AnyObject {
    /// `nil` means the report could not be read; an empty dictionary means it
    /// was read and carries no level for any device.
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void)
}

enum BluetoothBatteryReader {
    static func normalizedAddress(_ address: String) -> String {
        address
            .filter(\.isHexDigit)
            .uppercased()
    }

    static func parse(json: Data) -> [String: BluetoothBatteryLevel] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return [:]
        }

        var levels: [String: BluetoothBatteryLevel] = [:]
        // The addresses already carried, so one device reports one level.
        //
        // The collections are read connected-first, which makes a report that
        // lists one address in both — the shape a connect or a disconnect caught
        // mid-flight produces — keep the connected reading. Without this the
        // stale `device_not_connected` entry, read second, overwrote the live
        // one, so a row showing the current level silently fell back to the last
        // value macOS wrote down.
        var carriedAddresses: Set<String> = []
        for section in sections {
            for collectionKey in ["device_connected", "device_not_connected"] {
                guard let devices = section[collectionKey] as? [[String: Any]] else { continue }
                for entry in devices {
                    for value in entry.values {
                        guard let properties = value as? [String: Any],
                              let address = properties["device_address"] as? String,
                              !address.isEmpty else {
                            continue
                        }
                        let main = percentage(properties["device_batteryLevelMain"])
                            ?? percentage(properties["device_batteryLevel"])
                        let level = BluetoothBatteryLevel(
                            deviceAddress: address,
                            main: main,
                            left: percentage(properties["device_batteryLevelLeft"]),
                            right: percentage(properties["device_batteryLevelRight"]),
                            caseLevel: percentage(properties["device_batteryLevelCase"])
                        )
                        guard level.summary != nil else { continue }
                        let key = normalizedAddress(address)
                        // An address the normalizer cannot reduce names no
                        // device, so two of them are not necessarily the same
                        // one and both stay.
                        if !key.isEmpty {
                            guard carriedAddresses.insert(key).inserted else { continue }
                        }
                        levels[key] = level
                    }
                }
            }
        }
        return levels
    }

    private static func percentage(_ value: Any?) -> Int? {
        let number: Double
        switch value {
        case let value as NSNumber:
            number = value.doubleValue
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let withoutPercent = trimmed.hasSuffix("%")
                ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                : trimmed
            guard let parsed = Double(withoutPercent) else { return nil }
            number = parsed
        default:
            return nil
        }

        guard number.isFinite,
              number.rounded() == number,
              (0...100).contains(number) else {
            return nil
        }
        return Int(number)
    }
}
