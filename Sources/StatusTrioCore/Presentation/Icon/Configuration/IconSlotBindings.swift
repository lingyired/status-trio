import Foundation

enum IconSlotBindingsCodecError: Error, Equatable {
    case invalidRoot
    case missingSchemaVersion
    case unsupportedSchemaVersion(Int)
    case malformedData
}

/// One slot's ordered primary/fallback plugin bindings.
///
/// `primary == nil` means the slot is intentionally hidden. Unknown non-empty
/// plugin IDs are retained verbatim so an installed package that is temporarily
/// unavailable can come back without forgetting the user's selection.
struct IconSlotBindingSelection: Codable, Equatable, Sendable {
    var primary: IconContentBinding?
    var fallback: IconContentBinding?

    init(primary: IconContentBinding?, fallback: IconContentBinding? = nil) {
        self.primary = primary
        self.fallback = fallback
    }

    func normalized() -> Self {
        guard let primary else { return .init(primary: nil, fallback: nil) }
        var copy = self
        if copy.fallback == primary { copy.fallback = nil }
        return copy
    }

    var hasExternalBinding: Bool {
        primary?.isExternalSource == true || fallback?.isExternalSource == true
    }
}

/// Versioned slot bindings for all three icon slots.
///
/// This store is deliberately separate from `IconConfigurationV1.composition`:
/// the legacy enums keep representing built-in choices, while this payload can
/// also name external plugins whose IDs do not exist in the compile-time enum.
struct IconSlotBindingsV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var outerRing: IconSlotBindingSelection
    var center: IconSlotBindingSelection
    var footer: IconSlotBindingSelection

    static let classic = Self(
        schemaVersion: currentSchemaVersion,
        outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
        center: .init(primary: .init(pluginID: "builtin.legacy", presentationID: "center")),
        footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
    )

    func normalized() -> Self {
        var copy = self
        copy.outerRing = copy.outerRing.normalized()
        copy.center = copy.center.normalized()
        copy.footer = copy.footer.normalized()
        return copy
    }

    func selection(for slot: IconSlot) -> IconSlotBindingSelection {
        switch slot {
        case .outerRing: outerRing
        case .center: center
        case .footer: footer
        }
    }

    mutating func setSelection(_ selection: IconSlotBindingSelection, for slot: IconSlot) {
        switch slot {
        case .outerRing: outerRing = selection
        case .center: center = selection
        case .footer: footer = selection
        }
    }

    /// One-time import from the individual settings surface.
    ///
    /// The runtime has always rendered a projection of the individual settings,
    /// so that projection (not the possibly stale persisted V1 payload) is the
    /// correct migration source. Existing fallback choices are preserved. The
    /// bottom indicator is expressed by its legacy four-way source because the
    /// V1 footer enum only models volume/none.
    static func migrated(
        from configuration: IconConfigurationV1,
        bottomIndicatorSource: BottomIndicatorSource? = nil
    ) -> Self {
        let composition = configuration.composition
        let footerBinding: IconContentBinding?
        if let bottomIndicatorSource {
            footerBinding = IconContentLegacyAdapter.binding(for: bottomIndicatorSource)
        } else {
            footerBinding = IconContentLegacyAdapter.binding(for: composition.footer.primary)
        }
        return Self(
            schemaVersion: currentSchemaVersion,
            outerRing: .init(
                primary: IconContentLegacyAdapter.binding(for: composition.outerRing.primary),
                fallback: composition.outerRing.fallback.flatMap(IconContentLegacyAdapter.binding(for:))
            ),
            center: .init(
                primary: IconContentLegacyAdapter.binding(for: composition.center.primary),
                fallback: composition.center.fallback.flatMap(IconContentLegacyAdapter.binding(for:))
            ),
            footer: .init(primary: footerBinding),
            // The override policy stays in the V1 configuration; it is a
            // behaviour, not a slot selection.
            )
            .normalized()
    }
}

enum IconSlotBindingsCodec {
    static func encode(_ value: IconSlotBindingsV1) throws -> Data {
        guard value.schemaVersion == IconSlotBindingsV1.currentSchemaVersion else {
            throw IconSlotBindingsCodecError.unsupportedSchemaVersion(value.schemaVersion)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value.normalized())
    }

    static func decode(_ data: Data) throws -> IconSlotBindingsV1 {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw IconSlotBindingsCodecError.malformedData
        }
        guard let object = root as? [String: Any] else {
            throw IconSlotBindingsCodecError.invalidRoot
        }
        guard let version = object["schemaVersion"] as? Int else {
            throw IconSlotBindingsCodecError.missingSchemaVersion
        }
        guard version == IconSlotBindingsV1.currentSchemaVersion else {
            throw IconSlotBindingsCodecError.unsupportedSchemaVersion(version)
        }
        do {
            return try JSONDecoder().decode(IconSlotBindingsV1.self, from: data).normalized()
        } catch {
            throw IconSlotBindingsCodecError.malformedData
        }
    }
}
