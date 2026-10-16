import Carbon
import Foundation

/// One keyboard input source exactly as the Text Input Sources API reports it.
///
/// Deliberately raw: filtering and label derivation belong to
/// `InputSourceState.resolved`, which keeps every decision testable without
/// Carbon.
struct RawInputSource: Equatable, Sendable {
    let id: String
    let localizedName: String
    let languages: [String]
    let iconImageURL: URL?
    let isEnabled: Bool
    let isSelectCapable: Bool
}

/// Reads the system's input sources. Public Carbon TIS surface only; none of
/// the calls require a TCC grant.
protocol InputSourceReading {
    /// `TISCopyCurrentKeyboardInputSource`, the same source the system menu bar
    /// marks with a checkmark.
    func currentKeyboardInputSourceID() -> String?
    /// Every keyboard-category input source (`TISCreateInputSourceList`), in
    /// the order macOS returns them.
    func keyboardInputSources() -> [RawInputSource]
}

/// TIS posts these through `DistributedNotificationCenter`. The string values
/// are part of the public Carbon constants
/// (`kTISNotifySelectedKeyboardInputSourceChanged`); they are repeated here so
/// the main-actor controller does not have to import Carbon.
enum InputSourceNotifications {
    static let selectedSourceChanged = Notification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String
    )
    static let enabledSourcesChanged = Notification.Name(
        kTISNotifyEnabledKeyboardInputSourcesChanged as String
    )
}

struct SystemInputSourceReader: InputSourceReading {
    func currentKeyboardInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return Self.stringProperty(source, kTISPropertyInputSourceID)
    }

    func keyboardInputSources() -> [RawInputSource] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else {
            return []
        }

        return (list as NSArray).compactMap { item in
            guard let source = item as! TISInputSource? else { return nil }
            return Self.rawSource(source)
        }
    }

    private static func rawSource(_ source: TISInputSource) -> RawInputSource? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
        return RawInputSource(
            id: id,
            localizedName: stringProperty(source, kTISPropertyLocalizedName) ?? id,
            languages: stringArrayProperty(source, kTISPropertyInputSourceLanguages),
            iconImageURL: urlProperty(source, kTISPropertyIconImageURL),
            isEnabled: boolProperty(source, kTISPropertyInputSourceIsEnabled),
            isSelectCapable: boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
        )
    }

    // MARK: - CF property plumbing

    /// Only the get rule is used. Each `TISGetInputSourceProperty` value is
    /// owned by the input source and lives as long as it does, which is what
    /// `takeUnretainedValue` reflects.
    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        property(source, key) as? String
    }

    private static func stringArrayProperty(_ source: TISInputSource, _ key: CFString) -> [String] {
        property(source, key) as? [String] ?? []
    }

    private static func urlProperty(_ source: TISInputSource, _ key: CFString) -> URL? {
        guard let url = property(source, key) as? URL, url.isFileURL else { return nil }
        return url
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        (property(source, key) as? NSNumber)?.boolValue ?? false
    }
}
