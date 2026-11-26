import Darwin
import Foundation
import IOKit.ps

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
    /// The accessory this reading describes, as the power manager names it.
    ///
    /// Unlike the vendor/product pair, which every set of one model shares, this
    /// distinguishes two sets of the same model. It is the only safe way to
    /// attribute a reading to a device: `nil` means the source did not identify
    /// the accessory, and such a reading is never used rather than guessed onto
    /// whichever device happens to share its model or name.
    let identifier: String?
    let name: String
    let vendorID: Int?
    let productID: Int?
    let part: BluetoothAccessoryPart?
    /// The charge left, or `nil` when the source reports a charging state for
    /// this part but no readable capacity. Such a reading is still useful: it can
    /// supply the charging flag for a level another source already carries, so a
    /// missing capacity must not throw the state away.
    let percentage: Int?
    /// The accessory's explicit charging state, or `nil` when the source does not
    /// report one. Only a real boolean counts: a missing field, a number, or a
    /// string is unknown, never `false`.
    let isCharging: Bool?

    init(
        identifier: String?,
        name: String,
        vendorID: Int?,
        productID: Int?,
        part: BluetoothAccessoryPart?,
        percentage: Int?,
        isCharging: Bool? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.part = part
        self.percentage = percentage
        self.isCharging = isCharging
    }
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
        parse(documents: documents(in: xml))
    }

    /// The one parser both sources feed. IOKit hands back the same property
    /// dictionaries the XML decodes to, so a second field-parsing implementation
    /// is not needed: the only difference between the sources is how the
    /// dictionaries are obtained.
    static func parse(documents: [[String: Any]]) -> [BluetoothAccessoryBatteryLevel] {
        documents.flatMap(levels(from:))
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

    /// Every reading one power-source document yields.
    ///
    /// A document is either a whole accessory, or — when macOS nests its parts
    /// under `Combined Parts` — the parent of several part records. Each nested
    /// part is parsed as its own reading, inheriting the parent's identity only
    /// for the keys the part itself leaves out; capacity and charging state are
    /// never inherited, so a parent's charge cannot be handed to a bud.
    private static func levels(from document: [String: Any]) -> [BluetoothAccessoryBatteryLevel] {
        // The Mac's own battery is a power source too, and it is not an
        // accessory: its type is what keeps it out of this list.
        guard document["Type"] as? String == "Accessory Source" else { return [] }
        if let combined = document["Combined Parts"] as? [[String: Any]] {
            return combined.compactMap { part in
                level(from: mergingIdentity(of: document, into: part))
            }
        }
        return level(from: document).map { [$0] } ?? []
    }

    /// A nested part, with the parent's identity filled in for any identity key
    /// the part omits. Capacity and charging state are deliberately excluded: the
    /// part owns those, and inheriting the parent's would misattribute them.
    private static func mergingIdentity(
        of parent: [String: Any],
        into part: [String: Any]
    ) -> [String: Any] {
        var merged = part
        if merged["Type"] == nil { merged["Type"] = parent["Type"] }
        for key in ["Accessory Identifier", "Group Identifier", "Name",
                    "Vendor ID", "Product ID", "Accessory Category"] {
            if merged[key] == nil, let value = parent[key] { merged[key] = value }
        }
        return merged
    }

    private static func level(from document: [String: Any]) -> BluetoothAccessoryBatteryLevel? {
        guard document["Type"] as? String == "Accessory Source" else { return nil }
        let percentage = percentage(of: document)
        let isCharging = boolean(of: document["Is Charging"])
        // A reading is worth keeping when it carries a capacity or an explicit
        // charging state; a charging-only record still supplements a level another
        // source already has.
        guard percentage != nil || isCharging != nil else { return nil }
        return BluetoothAccessoryBatteryLevel(
            identifier: identifier(of: document),
            name: (document["Name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            vendorID: document["Vendor ID"] as? Int,
            productID: document["Product ID"] as? Int,
            part: BluetoothAccessoryPart(identifier: document["Part Identifier"] as? String),
            percentage: percentage,
            isCharging: isCharging
        )
    }

    /// A real boolean, or `nil` for anything else.
    ///
    /// `as? Bool` alone is unsafe: a plist `<integer>` decodes to `NSNumber`, and
    /// `NSNumber(value: 1) as? Bool` is `true`. Requiring the `CFBoolean` type
    /// keeps a number or a string from being read as "charging".
    private static func boolean(of value: Any?) -> Bool? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? number.boolValue : nil
        }
        if let flag = value as? Bool { return flag }
        return nil
    }

    /// The accessory's own identity, as the power manager writes it.
    ///
    /// This is a UUID from the power manager, not the device's Bluetooth address,
    /// so it is never compared to a device directly. It is kept because it is the
    /// only value that tells two sets of one model apart: the vendor/product pair
    /// and the name are shared by both. A source that omits it, or writes an
    /// empty string, is reported as `nil` and cannot be attributed by the caller.
    private static func identifier(of document: [String: Any]) -> String? {
        // `Accessory Identifier` is the accessory's own value. When macOS only
        // supplies the `Group Identifier`, the group names the same accessory's
        // parts and is the next-best stable owner; the empty string is never used.
        for key in ["Accessory Identifier", "Group Identifier"] {
            if let identifier = document[key] as? String {
                let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
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

/// Reads the accessory power sources out of `/usr/bin/pmset -g accps -xml`.
///
/// The XML form is asked for because the plain-text form drops the name of an
/// accessory it cannot resolve, and the name is one of the two things a reading
/// is matched to a device by. The subcommand itself is undocumented, so a future
/// macOS may stop answering it: a failed read reports no accessory rather than
/// failing anything, which leaves the paired-device report as the only source.
final class PmsetAccessoryBatteryWorker: @unchecked Sendable, BluetoothAccessoryBatteryReading {
    typealias OutputProvider = @Sendable () -> String?

    private static let queueLabel = "StatusTrio.PmsetAccessoryBatteryWorker"

    /// Guards `queue`, `queueGeneration` and `hasOutstandingRead`. `read` is
    /// called from the controller's main-actor context while a retired queue's
    /// block may still be running, so the retirement state is read and written
    /// under this lock rather than on whatever thread happens to call in.
    private let stateLock = NSLock()
    private var queue = DispatchQueue(label: queueLabel, qos: .utility)
    private var queueGeneration: UInt64 = 0
    private var hasOutstandingRead = false
    private let outputProvider: OutputProvider

    init(
        outputProvider: @escaping OutputProvider = { PmsetAccessoryBatteryWorker.readAccessoryPowerSources() }
    ) {
        self.outputProvider = outputProvider
    }

    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
        // A read that never returned would block this one behind it on the same
        // serial queue for the lifetime of the process, so retire that queue and
        // give this read a fresh one. `pmset` talks to the power manager and can
        // hang the same way `/usr/sbin/system_profiler` can, and the abandoned
        // block keeps the old queue alive until it eventually returns.
        let generation: UInt64
        let currentQueue: DispatchQueue
        (generation, currentQueue) = stateLock.withLock {
            if hasOutstandingRead {
                queueGeneration &+= 1
                queue = DispatchQueue(label: Self.queueLabel, qos: .utility)
            }
            hasOutstandingRead = true
            return (queueGeneration, queue)
        }

        let outputProvider = self.outputProvider
        currentQueue.async { [weak self] in
            let levels = outputProvider().map { BluetoothAccessoryBatteryReader.parse(xml: $0) }
            if let self {
                self.stateLock.withLock {
                    // Only the read on the current queue may clear the flag; a
                    // late completion from a retired queue must not, or the next
                    // read would queue behind a block that is still hung.
                    if generation == self.queueGeneration {
                        self.hasOutstandingRead = false
                    }
                }
            }
            completion(levels)
        }
    }

    /// Comfortably under the controller's read cadence; `pmset -g accps` is a
    /// quick query, so a deadline shorter than the profiler's is plenty.
    static let readTimeout: Duration = .seconds(4)

    /// The one bounded `pmset` accessory read in the app.
    ///
    /// `pmset -g accps` talks to the power manager and can hang the same way
    /// `/usr/sbin/system_profiler` can: `readDataToEndOfFile()` plus
    /// `waitUntilExit()` has no deadline, so a child that never exits — or a
    /// descendant that inherits the pipe — would block this worker's serial
    /// queue for the rest of the process. It runs through the shared bounded
    /// runner instead, so a stuck read ends itself and reports no accessory
    /// rather than stalling the chain. Parameters are injectable so the bound
    /// can be exercised with a fake child in tests.
    static func readAccessoryPowerSources(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/pmset"),
        arguments: [String] = ["-g", "accps", "-xml"],
        timeout: Duration = PmsetAccessoryBatteryWorker.readTimeout
    ) -> String? {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout
        )
        guard case .exited(let data) = outcome else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Reads the accessory power-source descriptions straight out of IOKit.
///
/// `IOPSCopyPowerSourcesByType` is what the power manager's own accessory
/// battery UI is built from, and it returns the same property dictionaries the
/// `pmset` XML decodes to, so both sources share `BluetoothAccessoryBatteryReader`.
/// The function is not public API, so it is resolved with `dlsym`: if the symbol
/// is missing, the read reports failure and the worker falls back to `pmset`
/// rather than losing the reading. A symbol once found is not re-probed; a read
/// that merely fails for the moment is not remembered as "unsupported".
enum IOKitAccessoryBatterySource {
    private typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    /// The argument that asks for every power source, accessories included.
    private static let allPowerSourcesType: Int32 = 0

    /// Resolved once for the life of the process. The handle is deliberately not
    /// closed: `dlsym` hands back a pointer into the image, and the cache only
    /// answers "is the symbol there", never "did the last read succeed".
    private static let copyPowerSourcesByType: CopyPowerSourcesByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return nil
        }
        guard let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)
    }()

    /// Whether the private symbol was found. Missing means every read must use
    /// the `pmset` fallback.
    static var isAvailable: Bool { copyPowerSourcesByType != nil }

    /// The parsed accessory readings, or `nil` when the private API is missing or
    /// the snapshot could not be obtained. An empty array is a successful read
    /// that found no accessory.
    static func readLevels() -> [BluetoothAccessoryBatteryLevel]? {
        guard let descriptions = descriptions() else { return nil }
        return BluetoothAccessoryBatteryReader.parse(documents: descriptions)
    }

    /// The raw description dictionaries, or `nil` on a hard failure. Only the
    /// private "by type" call is resolved dynamically; the snapshot walk uses the
    /// public `IOPS*` functions.
    static func descriptions() -> [[String: Any]]? {
        guard let copyPowerSourcesByType else { return nil }
        guard let snapshot = copyPowerSourcesByType(allPowerSourcesType)?.takeRetainedValue() else {
            return nil
        }
        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else {
            return nil
        }
        var descriptions: [[String: Any]] = []
        for element in list as NSArray {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, element as CFTypeRef)?
                    .takeUnretainedValue() as? [String: Any]
            else { continue }
            descriptions.append(description)
        }
        return descriptions
    }
}

/// The accessory battery reader the app runs: IOKit first, `pmset` fallback.
///
/// The IOKit path is the same data through a cheaper channel — no child process
/// for every refresh. It is used only when it actually reports an accessory; an
/// empty IOKit result or a missing symbol falls back to `pmset`, so a system
/// where the private coverage differs cannot silently lose the reading. The
/// fallback keeps its own hang protection; the IOKit attempt runs off the main
/// actor and is bounded by the CF call itself.
final class SystemAccessoryBatteryWorker: BluetoothAccessoryBatteryReading, @unchecked Sendable {
    typealias IOKitProvider = @Sendable () -> [BluetoothAccessoryBatteryLevel]?

    private static let queueLabel = "StatusTrio.SystemAccessoryBatteryWorker"

    private let iokitProvider: IOKitProvider
    private let fallback: any BluetoothAccessoryBatteryReading
    private let queue = DispatchQueue(label: queueLabel, qos: .utility)

    init(
        iokitProvider: @escaping IOKitProvider = { IOKitAccessoryBatterySource.readLevels() },
        fallback: any BluetoothAccessoryBatteryReading = PmsetAccessoryBatteryWorker()
    ) {
        self.iokitProvider = iokitProvider
        self.fallback = fallback
    }

    func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
        let iokitProvider = self.iokitProvider
        let fallback = self.fallback
        queue.async {
            if let levels = iokitProvider(), !levels.isEmpty {
                completion(levels)
                return
            }
            fallback.read(completion: completion)
        }
    }
}
