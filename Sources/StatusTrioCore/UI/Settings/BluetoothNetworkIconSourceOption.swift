import Foundation

/// One row of the icon-source menu.
///
/// The menu is built here rather than in the view body so its contents are
/// testable: a SwiftUI menu `Picker` leaves no AppKit control behind on
/// macOS 26, so nothing a test can inspect shows what the menu draws.
struct BluetoothNetworkIconSourceOption: Identifiable, Equatable {
    let source: BluetoothNetworkIconSource
    /// The device's name. `nil` for the audio entry, whose title is localized
    /// at render time.
    let title: String?
    let symbolName: String

    var id: String { source.id }

    /// The audio entry first, then every classified device in the order the
    /// panel list uses (connected first, the saved order within each group).
    ///
    /// Ghost devices are left out: they carry no class, so they have no glyph
    /// worth pinning and System Settings does not list them either.
    /// Whether the menu can offer a device at all.
    ///
    /// A ghost device has no class and is not in System Settings, so a list of
    /// nothing but ghosts is a list the menu cannot show — the same empty case
    /// as no grant or nothing paired.
    static func listsDevices(devices: [BluetoothDevice]) -> Bool {
        devices.contains { !$0.isUnpairedGhost }
    }

    static func options(
        devices: [BluetoothDevice],
        order: [String]
    ) -> [BluetoothNetworkIconSourceOption] {
        let audio = BluetoothNetworkIconSourceOption(
            source: .audioDevices,
            title: nil,
            symbolName: BluetoothNetworkIconSource.audioDeviceSymbol
        )

        let devices = BluetoothDeviceListPresentation.orderedDevices(
            devices.filter { !$0.isUnpairedGhost },
            using: order
        )

        return [audio] + devices.map { device in
            BluetoothNetworkIconSourceOption(
                source: .device(address: BluetoothBatteryReader.normalizedAddress(device.id)),
                title: device.name,
                symbolName: BluetoothDeviceRowIcon.symbolName(for: device)
            )
        }
    }
}
