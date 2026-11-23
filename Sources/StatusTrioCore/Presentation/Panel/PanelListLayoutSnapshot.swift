import Foundation

/// Which panel device list a layout snapshot belongs to. The raw values are the
/// persistence keys, so they must stay stable.
enum PanelListLayoutKey: String, Sendable {
    case bluetooth
    case volume
}

/// A compact, persistent description of a device list's last rendered layout.
///
/// The panel clears its device rows when it closes so no hardware or list data
/// stays resident while it is hidden. That makes the next open start from an
/// empty list, and the height grew as soon as the real rows arrived. Recording
/// the last layout lets the panel draw an equal-height skeleton while it
/// re-reads the rows, so the height only changes when the device count really
/// changed.
///
/// Only the row heights and two layout flags are stored: a handful of Doubles,
/// never a device name, address or icon, so the cache stays cheap and carries no
/// personal data.
struct PanelListLayoutSnapshot: Codable, Equatable, Sendable {
    /// The height each visible row contributed, in points, in display order.
    /// Estimating with the same metrics the list itself uses keeps the skeleton
    /// the same height as the rows it stands in for.
    var rowHeights: [Double]
    /// Whether the list showed its expand/collapse control.
    var hasExpansionButton: Bool
    /// Whether the section drew its device-list divider at all.
    var showsDeviceList: Bool

    /// Bound on persisted rows. A list never draws more than the configured
    /// limit (default 5), so this is generous while still refusing garbage.
    static let maximumRowCount = 24

    init(rowHeights: [Double], hasExpansionButton: Bool, showsDeviceList: Bool) {
        self.rowHeights = rowHeights
        self.hasExpansionButton = hasExpansionButton
        self.showsDeviceList = showsDeviceList
    }

    var rowCount: Int { rowHeights.count }

    var isEmpty: Bool { rowHeights.isEmpty && !showsDeviceList }

    /// Clamps untrusted persisted data: finite, non-negative heights, capped at
    /// `maximumRowCount`, and an expansion button only makes sense with rows.
    func sanitized() -> PanelListLayoutSnapshot {
        let cleaned = rowHeights.prefix(Self.maximumRowCount).map { height -> Double in
            guard height.isFinite else { return 0 }
            return min(max(0, height), 400)
        }
        return PanelListLayoutSnapshot(
            rowHeights: Array(cleaned),
            hasExpansionButton: hasExpansionButton && !cleaned.isEmpty,
            showsDeviceList: showsDeviceList
        )
    }
}

/// A bounded `UserDefaults` store for the per-list layout snapshots. Reading and
/// writing only touches a small `Data` blob; nothing here observes a device or
/// keeps a hardware reference alive while the panel is closed.
struct PanelListLayoutSnapshotStore {
    private let defaults: UserDefaults
    private static let keyPrefix = "panelListLayoutSnapshot."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func defaultsKey(_ key: PanelListLayoutKey) -> String {
        Self.keyPrefix + key.rawValue
    }

    /// The last saved layout, or nil when nothing usable was recorded. A snapshot
    /// with no rows and no list is treated as absent.
    func snapshot(for key: PanelListLayoutKey) -> PanelListLayoutSnapshot? {
        guard
            let data = defaults.data(forKey: defaultsKey(key)),
            let decoded = try? JSONDecoder().decode(PanelListLayoutSnapshot.self, from: data)
        else { return nil }
        let snapshot = decoded.sanitized()
        return snapshot.isEmpty ? nil : snapshot
    }

    /// Persists a snapshot, skipping an unchanged write so a periodically
    /// updated list does not hit `UserDefaults` on every tick. Passing nil, or an
    /// empty snapshot, clears the entry.
    func save(_ snapshot: PanelListLayoutSnapshot?, for key: PanelListLayoutKey) {
        guard let snapshot else {
            defaults.removeObject(forKey: defaultsKey(key))
            return
        }
        let sanitized = snapshot.sanitized()
        guard !sanitized.isEmpty else {
            defaults.removeObject(forKey: defaultsKey(key))
            return
        }
        if let existing = self.snapshot(for: key), existing == sanitized { return }
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        defaults.set(data, forKey: defaultsKey(key))
    }
}
