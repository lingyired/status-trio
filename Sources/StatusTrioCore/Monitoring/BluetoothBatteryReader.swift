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

    /// Each channel's explicit charging state, or `nil` when unknown. The primary
    /// report never supplies this; the accessory power sources add it after the
    /// level is published, and the four fields are merged independently so one
    /// bud's state is never inferred from another's.
    var mainIsCharging: Bool? = nil
    var leftIsCharging: Bool? = nil
    var rightIsCharging: Bool? = nil
    var caseIsCharging: Bool? = nil

    /// The level as the pieces a row draws, or `nil` when the report carries no
    /// channel for this device at all.
    ///
    /// The charging case is a glyph rather than the word "Case"; the percentage
    /// beside it stays text, because the word was the part with no room. A channel
    /// that is charging draws a bolt between its label and its percentage. A
    /// channel with no level is not drawn at all, so a charging flag never becomes
    /// an empty bolt with no charge to point at.
    var segments: [BluetoothBatterySegment]? {
        var channels: [[BluetoothBatterySegment]] = []
        if let main {
            channels.append(Self.channel(prefix: nil, value: main, isCharging: mainIsCharging))
        }
        if let left {
            channels.append(Self.channel(prefix: "L ", value: left, isCharging: leftIsCharging))
        }
        if let right {
            channels.append(Self.channel(prefix: "R ", value: right, isCharging: rightIsCharging))
        }
        if let caseLevel {
            channels.append(Self.caseChannel(value: caseLevel, isCharging: caseIsCharging))
        }
        guard !channels.isEmpty else { return nil }
        var pieces: [BluetoothBatterySegment] = []
        for (index, channel) in channels.enumerated() {
            if index > 0 { pieces.append(.text(Self.separator)) }
            pieces.append(contentsOf: channel)
        }
        return pieces
    }

    /// Whether any channel that is actually drawn is charging. The drawn text
    /// hides its glyph from accessibility, so the row asks this to add the
    /// localized word a screen reader otherwise misses.
    var hasVisibleCharging: Bool {
        (main != nil && mainIsCharging == true)
            || (left != nil && leftIsCharging == true)
            || (right != nil && rightIsCharging == true)
            || (caseLevel != nil && caseIsCharging == true)
    }

    /// One labelled channel's pieces: optional "L "/"R " prefix, a bolt when it is
    /// charging, then the percentage. The bolt's text label is empty on purpose —
    /// it is decoration, and the spelling a text surface needs is added once for
    /// the whole row by `hasVisibleCharging`, in the localized UI layer.
    private static func channel(
        prefix: String?,
        value: Int,
        isCharging: Bool?
    ) -> [BluetoothBatterySegment] {
        // Not charging (or unknown) keeps the original single text piece, so the
        // existing wording and its pinned segments do not change.
        guard isCharging == true else {
            return [.text("\(prefix ?? "")\(value)%")]
        }
        var pieces: [BluetoothBatterySegment] = []
        if let prefix { pieces.append(.text(prefix)) }
        pieces.append(.symbol(name: chargingSymbolName, label: ""))
        pieces.append(.text("\(value)%"))
        return pieces
    }

    /// The charging-case channel: its glyph stands in for the word "Case", the
    /// bolt follows a space when charging, then the percentage — so the bolt sits
    /// right against the number exactly as it does for L/R, and the case glyph
    /// stays the label rather than being glued to the bolt.
    private static func caseChannel(value: Int, isCharging: Bool?) -> [BluetoothBatterySegment] {
        var pieces: [BluetoothBatterySegment] = [
            .symbol(name: caseSymbolName, label: caseTextLabel)
        ]
        guard isCharging == true else {
            pieces.append(.text(" \(value)%"))
            return pieces
        }
        pieces.append(.text(" "))
        pieces.append(.symbol(name: chargingSymbolName, label: ""))
        pieces.append(.text("\(value)%"))
        return pieces
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

    /// The charging bolt, drawn beside a channel that reports charging. `bolt.fill`
    /// ships with every macOS the app supports, so it needs no availability gate.
    static let chargingSymbolName = "bolt.fill"

    /// What the text-only rendering says where the row draws the glyph.
    static let caseTextLabel = "Case"

    /// Between two channels of one device.
    private static let separator = " · "
}

extension BluetoothBatteryLevel {
    /// This level with the charging fields the accessory source supplies, filling
    /// only channels that already carry a level here and whose state is still
    /// unknown. The percentages are never touched: this can add a bolt, never a
    /// number, and a channel with no level is not given a state the row cannot
    /// draw anyway.
    func fillingCharging(from supplement: BluetoothBatteryLevel?) -> BluetoothBatteryLevel {
        guard let supplement else { return self }
        var result = self
        if main != nil, mainIsCharging == nil { result.mainIsCharging = supplement.mainIsCharging }
        if left != nil, leftIsCharging == nil { result.leftIsCharging = supplement.leftIsCharging }
        if right != nil, rightIsCharging == nil { result.rightIsCharging = supplement.rightIsCharging }
        if caseLevel != nil, caseIsCharging == nil { result.caseIsCharging = supplement.caseIsCharging }
        return result
    }
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
        // Disconnected profiler entries retain historical percentages without a
        // measurement timestamp. Only connected entries can supply live levels;
        // deduplicate their normalized addresses across all controller sections.
        var carriedAddresses: Set<String> = []
        for section in sections {
            guard let devices = section["device_connected"] as? [[String: Any]] else { continue }
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

final class SystemProfilerBluetoothBatteryWorker: @unchecked Sendable, BluetoothBatteryReading {
    typealias OutputProvider = @Sendable () -> Data?
    private let queue = DispatchQueue(label: "StatusTrio.SystemProfilerBluetoothBatteryWorker")
    private let outputProvider: OutputProvider
    private let reportCache: BluetoothProfilerReportCache

    init(
        outputProvider: @escaping OutputProvider = SystemProfilerBluetoothBatteryWorker.readSystemProfilerOutput,
        reportCache: BluetoothProfilerReportCache = .shared
    ) {
        self.outputProvider = outputProvider
        self.reportCache = reportCache
    }

    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        queue.async {
            let data: Data?
            if let cached = self.reportCache.freshData() {
                // Bytes that were only read are never stored back: the freshness
                // window runs from the last `store`, so re-stamping them would
                // both extend their life and let them overwrite a newer report
                // the device worker stored in the meantime.
                data = cached
            } else {
                let cacheEpoch = self.reportCache.currentEpoch
                data = self.outputProvider()
                if let fetched = data {
                    // This read genuinely fetched, so it may seed the cache for
                    // a read that happens moments later.
                    self.reportCache.store(fetched, ifCurrent: cacheEpoch)
                }
            }
            guard let data else {
                // A report that could not be read is not an empty report.
                completion(nil)
                return
            }
            completion(BluetoothBatteryReader.parse(json: data))
        }
    }

    /// The battery and device readers want the same report; share the bounded
    /// read so there is one deadline and one place that reaps the child.
    static func readSystemProfilerOutput() -> Data? {
        SystemProfilerBluetoothPairedDeviceWorker.readSystemProfilerOutput()
    }
}
