import CoreGraphics

/// Layout the status panel's Bluetooth section shares between its own row and
/// the device rows underneath it. Both reserve the same icon column, so the
/// device glyphs and their names line up under the section's icon — the same
/// 24-point column the volume output list and its rows use.
enum BluetoothPanelMetrics {
    /// The width the section icon and every device glyph are centred in.
    static let iconColumnWidth: CGFloat = 24

    /// The gap between that column and the text that follows it.
    static let iconTextSpacing: CGFloat = 10

    /// The gap between a component row's name line and its battery line. Kept
    /// tight so the two lines read as one group.
    static let componentBatteryLineSpacing: CGFloat = 2

    /// Extra space below a component row only, so its second line does not crowd
    /// the next device. Deliberately not applied to inline rows or to the list's
    /// global row spacing — those stay compact.
    static let componentRowBottomPadding: CGFloat = 5
}

/// How tall one device row is in the list, per the layout it draws. The list
/// adds these up to decide whether the rows outgrow the panel and have to scroll;
/// a component row renders a second line, so it counts for more than an inline
/// one. A single layout policy therefore maps to a single estimated height —
/// otherwise the list would be back to guessing from the device count.
enum BluetoothDeviceRowMetrics {
    /// The single-line row. The badge's icon column sets its height, and the one
    /// text line is never taller, so this stays tied to that column.
    static let inlineHeight: CGFloat = BluetoothPanelMetrics.iconColumnWidth

    /// The two-line row's own content height: the name's line plus the level's
    /// line and the tight gap between them. Measured from a rendered row rather
    /// than guessed, at the row's own body/caption sizes and
    /// `componentBatteryLineSpacing`.
    static let componentContentHeight: CGFloat = 31

    /// The extra source/time line shown for trusted-phone observations.
    static let mobileObservationLineHeight: CGFloat = 15

    /// The full height a component row contributes: its two lines plus the extra
    /// bottom breathing room the row actually draws. Derived from the shared
    /// spacing metrics so the row and this estimate can never drift apart.
    static var componentHeight: CGFloat {
        componentContentHeight + BluetoothPanelMetrics.componentRowBottomPadding
    }

    /// The height one device's row contributes, read from the same layout policy
    /// the row itself draws with.
    static func estimatedHeight(
        for device: BluetoothDevice,
        batteryLevels: [String: BluetoothBatteryLevel],
        hasMobileDetails: Bool = false
    ) -> CGFloat {
        let baseHeight = BluetoothDevicePresentation.batteryLayout(
            for: device,
            batteryLevels: batteryLevels
        ) == .components
            ? componentHeight
            : inlineHeight
        return hasMobileDetails ? baseHeight + mobileObservationLineHeight : baseHeight
    }
}
