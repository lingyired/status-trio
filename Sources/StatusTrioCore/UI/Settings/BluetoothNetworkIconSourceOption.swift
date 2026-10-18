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

    /// One flat, de-duplicated menu for a centre glyph picker.
    ///
    /// A picker row is keyed by its `symbolName`, so the list must not repeat a
    /// glyph: the full `BluetoothAudioIconChoice` product set leads (AirPods by
    /// generation, Beats, HomePod, Hi-Fi speaker, …), then the live device-type
    /// glyphs, then the legacy featured audio entry `airpodspro`. The first
    /// occurrence of a symbol wins, so a device type that is already in the
    /// product set does not appear twice. Rows carry `title` only when a pinned
    /// device supplies one; callers localize product rows from the choice.
    static func glyphOptions(
        devices: [BluetoothDevice],
        order: [String],
        audioChoices: [BluetoothAudioIconChoice],
        savedSymbol: String? = nil
    ) -> [GlyphOption] {
        var seen = Set<String>()
        var result: [GlyphOption] = []

        func append(symbolName: String, choice: BluetoothAudioIconChoice?, title: String?) {
            guard !symbolName.isEmpty, seen.insert(symbolName).inserted else { return }
            result.append(GlyphOption(
                symbolName: symbolName,
                choice: choice,
                title: title,
                isSavedUnsupportedSymbol: savedSymbol == symbolName && choice == nil && title == nil
            ))
        }

        for choice in audioChoices {
            guard let symbolName = choice.symbolName else { continue }
            append(symbolName: symbolName, choice: choice, title: nil)
        }

        // Device-type glyphs from the live catalogue first, then the featured
        // current-audio-output glyph `airpodspro`, which is a device type too.
        for option in options(devices: devices, order: order) where option.source != .audioDevices {
            append(symbolName: option.symbolName, choice: nil, title: option.title)
        }
        append(symbolName: BluetoothNetworkIconSource.audioDeviceSymbol, choice: nil, title: nil)

        if let savedSymbol {
            append(symbolName: savedSymbol, choice: nil, title: nil)
        }
        return result
    }

    /// Convenience overload for the views: resolve the product set from the
    /// running OS once, then reuse the pure list builder above.
    @MainActor
    static func glyphOptions(
        devices: [BluetoothDevice],
        order: [String],
        savedSymbol: String? = nil
    ) -> [GlyphOption] {
        glyphOptions(
            devices: devices,
            order: order,
            audioChoices: IconPresentationResourceResolver.availableBluetoothAudioIconChoices,
            savedSymbol: savedSymbol
        )
    }

    /// A row of the centre glyph picker. `choice` is non-`nil` for the product
    /// glyph set so the row can draw the localized product name; device rows
    /// carry their own `title`; a saved unsupported symbol stays selectable.
    struct GlyphOption: Identifiable, Equatable {
        let symbolName: String
        let choice: BluetoothAudioIconChoice?
        let title: String?
        let isSavedUnsupportedSymbol: Bool

        var id: String { symbolName }
    }
}
