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
            identifier: identifier(of: document),
            name: (document["Name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            vendorID: document["Vendor ID"] as? Int,
            productID: document["Product ID"] as? Int,
            part: BluetoothAccessoryPart(identifier: document["Part Identifier"] as? String),
            percentage: percentage
        )
    }

    /// The accessory's own identity, as the power manager writes it.
    ///
    /// This is a UUID from the power manager, not the device's Bluetooth address,
    /// so it is never compared to a device directly. It is kept because it is the
    /// only value that tells two sets of one model apart: the vendor/product pair
    /// and the name are shared by both. A source that omits it, or writes an
    /// empty string, is reported as `nil` and cannot be attributed by the caller.
    private static func identifier(of document: [String: Any]) -> String? {
        guard let identifier = document["Accessory Identifier"] as? String else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
