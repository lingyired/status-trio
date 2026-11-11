import AppKit
import CryptoKit
import Foundation

struct SettingsDeviceInventory: Sendable {
    var outputUIDs: Set<String>
    var inputUIDs: Set<String>
    var displayIDs: Set<String>
    var bluetoothAddresses: Set<String>
    var betterDisplayUUIDs: Set<String>

    init(
        outputUIDs: Set<String> = [], inputUIDs: Set<String> = [],
        displayIDs: Set<String> = [], bluetoothAddresses: Set<String> = [],
        betterDisplayUUIDs: Set<String> = []
    ) {
        self.outputUIDs = outputUIDs
        self.inputUIDs = inputUIDs
        self.displayIDs = displayIDs
        self.bluetoothAddresses = bluetoothAddresses
        self.betterDisplayUUIDs = betterDisplayUUIDs
    }
}

/// Trusted, process-local undo state. Deliberately not Codable: raw identities
/// never belong in a transferable document. Only the archive creates this value.
struct SettingsDeviceLocalState: Sendable {
    fileprivate var outputOrder: [String]
    fileprivate var hiddenOutputs: Set<String>
    fileprivate var inputOrder: [String]
    fileprivate var hiddenInputs: Set<String>
    fileprivate var volumes: [String: ExternalVolumeConfiguration]
    fileprivate var brightness: [String: ExternalBrightnessConfiguration]
    fileprivate var hiddenDisplays: Set<String>
    fileprivate var bluetoothOrder: [String]
    fileprivate var hiddenBluetooth: Set<String>
    fileprivate var revealedBluetooth: Set<String>
    fileprivate var centerAddress: String?
    fileprivate var centerSymbol: String?

    @MainActor
    fileprivate init(_ store: SettingsStore) {
        outputOrder = store.outputDeviceOrder
        hiddenOutputs = store.hiddenOutputDeviceUIDs
        inputOrder = store.inputDeviceOrder
        hiddenInputs = store.hiddenInputDeviceUIDs
        volumes = store.externalVolumeConfigurations
        brightness = store.externalBrightnessConfigurations
        hiddenDisplays = store.hiddenBrightnessDisplayIDs
        bluetoothOrder = store.bluetoothDeviceOrder
        hiddenBluetooth = store.hiddenBluetoothDeviceAddresses
        revealedBluetooth = store.revealedGhostBluetoothDeviceAddresses
        centerAddress = store.bluetoothNetworkIconDeviceAddress
        centerSymbol = store.bluetoothNetworkIconSymbolName
    }
}

@MainActor
enum SettingsDeviceArchive {
    private static let sections = ["audioOutputs", "audioInputs", "brightnessDisplays", "bluetoothDevices"]

    static func captureLocalState(_ store: SettingsStore) -> SettingsDeviceLocalState {
        SettingsDeviceLocalState(store)
    }

    /// Exact replacement, not a merge: removes entries introduced by import and
    /// restores disconnected devices. BLE/Apple consent and selections are untouched.
    static func restoreLocalState(_ state: SettingsDeviceLocalState, to store: SettingsStore) {
        store.replaceTransferredDeviceLists(
            outputOrder: state.outputOrder, hiddenOutputs: state.hiddenOutputs,
            inputOrder: state.inputOrder, hiddenInputs: state.hiddenInputs,
            volumes: state.volumes, brightness: state.brightness,
            hiddenDisplays: state.hiddenDisplays, bluetoothOrder: state.bluetoothOrder
        )
        if store.hiddenBluetoothDeviceAddresses != state.hiddenBluetooth {
            store.hiddenBluetoothDeviceAddresses = state.hiddenBluetooth
        }
        if store.revealedGhostBluetoothDeviceAddresses != state.revealedBluetooth {
            store.revealedGhostBluetoothDeviceAddresses = state.revealedBluetooth
        }
        if store.bluetoothNetworkIconDeviceAddress != state.centerAddress
            || store.bluetoothNetworkIconSymbolName != state.centerSymbol {
            store.setBluetoothNetworkIconDevice(address: state.centerAddress, symbolName: state.centerSymbol)
        }
    }

    /// Includes remembered/disconnected identities, for trusted local backup matching.
    /// Normal import must instead supply the currently known hardware inventory.
    static func localInventory(_ store: SettingsStore) -> SettingsDeviceInventory {
        let state = captureLocalState(store)
        return SettingsDeviceInventory(
            outputUIDs: Set(state.outputOrder).union(state.hiddenOutputs).union(state.volumes.keys),
            inputUIDs: Set(state.inputOrder).union(state.hiddenInputs),
            displayIDs: Set(state.brightness.keys).union(state.hiddenDisplays),
            bluetoothAddresses: Set((state.bluetoothOrder + Array(state.hiddenBluetooth)
                + Array(state.revealedBluetooth) + [state.centerAddress].compactMap { $0 })
                .compactMap { classicAddress($0) }),
            betterDisplayUUIDs: Set(state.volumes.values.compactMap(\.betterDisplayUUID))
                .union(state.brightness.values.compactMap(\.betterDisplayUUID))
        )
    }

    static func snapshot(_ store: SettingsStore) -> [String: SettingsTransferValue] {
        let state = captureLocalState(store)
        let inventory = localInventory(store)
        var outputs: [String: SettingsTransferValue] = [:]
        for id in inventory.outputUIDs where !id.isEmpty {
            var record: [String: SettingsTransferValue] = [
                "hidden": .bool(state.hiddenOutputs.contains(id)),
                "volume": state.volumes[id].map { configuration($0.backend.rawValue, uuid: $0.betterDisplayUUID) } ?? .null
            ]
            if let index = state.outputOrder.firstIndex(of: id) { record["order"] = .number(Double(index)) }
            outputs[token("output", id)] = .object(record)
        }
        var inputs: [String: SettingsTransferValue] = [:]
        for id in inventory.inputUIDs where !id.isEmpty {
            var record: [String: SettingsTransferValue] = ["hidden": .bool(state.hiddenInputs.contains(id))]
            if let index = state.inputOrder.firstIndex(of: id) { record["order"] = .number(Double(index)) }
            inputs[token("input", id)] = .object(record)
        }
        var displays: [String: SettingsTransferValue] = [:]
        for id in inventory.displayIDs where !id.isEmpty {
            displays[token("display", id)] = .object([
                "hidden": .bool(state.hiddenDisplays.contains(id)),
                "brightness": state.brightness[id].map { configuration($0.backend.rawValue, uuid: $0.betterDisplayUUID) } ?? .null
            ])
        }
        let order = state.bluetoothOrder.compactMap { classicAddress($0) }
        let hidden = Set(state.hiddenBluetooth.compactMap { classicAddress($0) })
        let revealed = Set(state.revealedBluetooth.compactMap { classicAddress($0) })
        var bluetooth: [String: SettingsTransferValue] = [:]
        for id in inventory.bluetoothAddresses {
            var record: [String: SettingsTransferValue] = [
                "hidden": .bool(hidden.contains(id)), "revealed": .bool(revealed.contains(id))
            ]
            if let index = order.firstIndex(of: id) { record["order"] = .number(Double(index)) }
            bluetooth[token("bluetooth", id)] = .object(record)
        }
        var result: [String: SettingsTransferValue] = [
            "audioOutputs": .object(outputs), "audioInputs": .object(inputs),
            "brightnessDisplays": .object(displays), "bluetoothDevices": .object(bluetooth)
        ]
        // SF Symbol identifiers are appearance preferences, not device metadata.
        // Never export device names, unvalidated strings or BLE/mobile identities.
        // Explicit null restores "follow current"; an absent field preserves selection.
        if state.centerAddress == nil {
            result["bluetoothCenterDevice"] = .null
        } else if let address = state.centerAddress.flatMap({ classicAddress($0) }),
                  let symbol = state.centerSymbol, isSafeSymbol(symbol) {
            result["bluetoothCenterDevice"] = .object([
                "device": .string(token("bluetooth", address)), "symbol": .string(symbol)
            ])
        }
        return result
    }

    /// Returns matched local identities for in-memory apply only. Never serialize
    /// prepared values; snapshot is the only transferable representation.
    static func prepare(
        _ values: [String: SettingsTransferValue], inventory: SettingsDeviceInventory
    ) -> (values: [String: SettingsTransferValue], warnings: [String]) {
        var result: [String: SettingsTransferValue] = [:]
        var warnings: [String] = []
        let identities: [String: [String: String]] = [
            "audioOutputs": matches("output", inventory.outputUIDs),
            "audioInputs": matches("input", inventory.inputUIDs),
            "brightnessDisplays": matches("display", inventory.displayIDs),
            "bluetoothDevices": matches("bluetooth", Set(inventory.bluetoothAddresses.compactMap { classicAddress($0) }))
        ]
        let betterDisplay = matches("betterDisplay", inventory.betterDisplayUUIDs)
        for key in values.keys.sorted() where !sections.contains(key) && key != "bluetoothCenterDevice" {
            warnings.append("devices.unknown")
        }
        for section in sections {
            guard let value = values[section] else { continue }
            guard case .object(let entries) = value, entries.count <= 10_000 else {
                warnings.append("devices.\(section).invalid")
                continue
            }
            var prepared: [String: SettingsTransferValue] = [:]
            for hash in entries.keys.sorted() {
                guard let id = identities[section]?[hash] else {
                    warnings.append("devices.\(section).unmatched")
                    continue
                }
                guard case .object(let record) = entries[hash] else {
                    warnings.append("devices.\(section).invalid")
                    continue
                }
                let fields: Set<String> = section == "audioOutputs" ? ["hidden", "order", "volume"]
                    : section == "audioInputs" ? ["hidden", "order"]
                    : section == "brightnessDisplays" ? ["hidden", "brightness"] : ["hidden", "order", "revealed"]
                var valid: [String: SettingsTransferValue] = [:]
                for field in record.keys.sorted() {
                    guard fields.contains(field), let value = record[field] else {
                        warnings.append("devices.\(section).unknown")
                        continue
                    }
                    switch field {
                    case "hidden", "revealed":
                        if case .bool = value { valid[field] = value }
                        else { warnings.append("devices.\(section).\(field).invalid") }
                    case "order":
                        if rank(value) != nil { valid[field] = value }
                        else { warnings.append("devices.\(section).order.invalid") }
                    default:
                        if let config = prepareConfiguration(value, brightness: field == "brightness", betterDisplay: betterDisplay) {
                            valid[field] = config
                        } else {
                            warnings.append("devices.\(section).\(field).invalid")
                        }
                    }
                }
                if !valid.isEmpty { prepared[id] = .object(valid) }
            }
            if !prepared.isEmpty { result[section] = .object(prepared) }
        }
        if let value = values["bluetoothCenterDevice"] {
            if case .null = value {
                result["bluetoothCenterDevice"] = .null
            } else if case .object(let selection) = value,
                      Set(selection.keys) == ["device", "symbol"],
                      case .string(let hash) = selection["device"],
                      case .string(let symbol) = selection["symbol"] {
                if !isSafeSymbol(symbol) {
                    warnings.append("devices.bluetoothCenterDevice.symbol.invalid")
                } else if let id = identities["bluetoothDevices"]?[hash] {
                    result["bluetoothCenterDevice"] = .object(["device": .string(id), "symbol": .string(symbol)])
                } else {
                    warnings.append("devices.bluetoothCenterDevice.device.unmatched")
                }
            } else {
                warnings.append("devices.bluetoothCenterDevice.invalid")
            }
        }
        return (result, warnings)
    }

    static func apply(_ values: [String: SettingsTransferValue], to store: SettingsStore) {
        var state = captureLocalState(store)
        for section in sections {
            guard case .object(let entries) = values[section] else { continue }
            var ordered: [(id: String, rank: Double)] = []
            for id in entries.keys.sorted() where !id.isEmpty {
                guard case .object(let record) = entries[id] else { continue }
                if let value = record["order"], let index = rank(value) { ordered.append((id, index)) }
                if case .bool(let hidden) = record["hidden"] {
                    switch section {
                    case "audioOutputs": update(&state.hiddenOutputs, id, hidden)
                    case "audioInputs": update(&state.hiddenInputs, id, hidden)
                    case "brightnessDisplays": update(&state.hiddenDisplays, id, hidden)
                    default: update(&state.hiddenBluetooth, id, hidden)
                    }
                }
                if section == "bluetoothDevices", case .bool(let revealed) = record["revealed"] {
                    update(&state.revealedBluetooth, id, revealed)
                }
                if section == "audioOutputs", let value = record["volume"] {
                    if case .null = value { state.volumes.removeValue(forKey: id) }
                    else if let config = volume(value) {
                        if config == .default { state.volumes.removeValue(forKey: id) }
                        else { state.volumes[id] = config }
                    }
                }
                if section == "brightnessDisplays", let value = record["brightness"] {
                    if case .null = value { state.brightness.removeValue(forKey: id) }
                    else if let config = brightness(value) { state.brightness[id] = config }
                }
            }
            guard !ordered.isEmpty else { continue }
            let order = ordered.sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank }.map(\.id)
            switch section {
            case "audioOutputs": state.outputOrder = SettingsStore.mergedDeviceOrder(order, previous: state.outputOrder)
            case "audioInputs": state.inputOrder = SettingsStore.mergedDeviceOrder(order, previous: state.inputOrder)
            case "bluetoothDevices": state.bluetoothOrder = SettingsStore.mergedDeviceOrder(order, previous: state.bluetoothOrder)
            default: break
            }
        }
        if case .null = values["bluetoothCenterDevice"] {
            state.centerAddress = nil
            state.centerSymbol = nil
        } else if case .object(let selection) = values["bluetoothCenterDevice"],
                  case .string(let address) = selection["device"], let normalized = classicAddress(address),
                  case .string(let symbol) = selection["symbol"], isSafeSymbol(symbol) {
            state.centerAddress = normalized
            state.centerSymbol = symbol
        }
        restoreLocalState(state, to: store)
    }

    private static func token(_ domain: String, _ id: String) -> String {
        SHA256.hash(data: Data("status-trio.device.v1:\(domain):\(id)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func matches(_ domain: String, _ ids: Set<String>) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ids.filter { !$0.isEmpty }.map { (token(domain, $0), $0) })
    }

    private static func classicAddress(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "-" }) else { return nil }
        let normalized = BluetoothBatteryReader.normalizedAddress(value)
        return normalized.count == 12 ? normalized : nil
    }

    private static func isSafeSymbol(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard !value.isEmpty, value.utf8.count <= 128,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil
    }

    private static func rank(_ value: SettingsTransferValue) -> Double? {
        guard case .number(let number) = value, number.isFinite,
              number >= 0, number <= 100_000, number.rounded() == number else { return nil }
        return number
    }

    private static func update(_ set: inout Set<String>, _ id: String, _ included: Bool) {
        if included { set.insert(id) } else { set.remove(id) }
    }

    private static func configuration(_ backend: String, uuid: String?) -> SettingsTransferValue {
        .object([
            "backend": .string(backend),
            "betterDisplayUUID": uuid.map { .string(token("betterDisplay", $0)) } ?? .null
        ])
    }

    private static func prepareConfiguration(
        _ value: SettingsTransferValue, brightness: Bool, betterDisplay: [String: String]
    ) -> SettingsTransferValue? {
        if case .null = value { return .null }
        guard case .object(let fields) = value,
              Set(fields.keys).isSubset(of: ["backend", "betterDisplayUUID"]),
              case .string(let backend) = fields["backend"],
              brightness ? BrightnessBackend(rawValue: backend) != nil : ExternalVolumeBackend(rawValue: backend) != nil
        else { return nil }
        var uuid: SettingsTransferValue = .null
        if let association = fields["betterDisplayUUID"], association != .null {
            guard backend == "betterDisplay", case .string(let hash) = association,
                  let local = betterDisplay[hash] else { return nil }
            uuid = .string(local)
        }
        return .object(["backend": .string(backend), "betterDisplayUUID": uuid])
    }

    private static func volume(_ value: SettingsTransferValue) -> ExternalVolumeConfiguration? {
        guard case .object(let fields) = value, case .string(let name) = fields["backend"],
              let backend = ExternalVolumeBackend(rawValue: name) else { return nil }
        let uuid: String? = if case .string(let value) = fields["betterDisplayUUID"] { value } else { nil }
        return ExternalVolumeConfiguration(backend: backend, betterDisplayUUID: uuid).sanitized()
    }

    private static func brightness(_ value: SettingsTransferValue) -> ExternalBrightnessConfiguration? {
        guard case .object(let fields) = value, case .string(let name) = fields["backend"],
              let backend = BrightnessBackend(rawValue: name) else { return nil }
        let uuid: String? = if case .string(let value) = fields["betterDisplayUUID"] { value } else { nil }
        return ExternalBrightnessConfiguration(backend: backend, betterDisplayUUID: uuid).sanitized()
    }
}
