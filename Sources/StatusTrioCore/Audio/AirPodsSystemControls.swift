import CoreAudio
import Foundation
import IOBluetooth

struct AirPodsSystemOption: Equatable, Identifiable {
    let title: String
    let selected: Bool
    var mode: BluetoothListeningMode? = nil
    var symbol: String? = nil
    var dimWaves = false
    var id: String { title }
}

struct AirPodsSystemSnapshot: Equatable {
    var conversation: [AirPodsSystemOption] = []
    var spatial: [AirPodsSystemOption] = []
    var adaptive: Int?
    var loaded = false
    var conversationLoaded = false
    var spatialLoaded = false
    var supportsSpatial: Bool? = nil
    var supportsConversation: Bool? = nil
}

/// Hardware support is distinct from temporary playback/API availability.
/// Unknown variants defer to runtime capability reporting.
struct AirPodsFeatureSupport {
    let spatial: Bool?
    let conversation: Bool?

    init(modelUID: String?) {
        guard let model = AirPodsModel(modelUID: modelUID) else {
            spatial = nil
            conversation = nil
            return
        }
        spatial = model != .airPods
        let product = (modelUID ?? "").split(separator: " ").first
            .flatMap { BluetoothHexIdentifier.value(from: String($0)) }
        switch model {
        case .airPods, .airPodsGen3, .airPodsProGen1:
            conversation = false
        case .airPodsGen4 where product == 0x2019:
            conversation = false // AirPods 4 without ANC
        case .airPodsMax where product == 0x200A || product == 0x201F:
            conversation = false // Lightning / USB-C first generation
        default:
            conversation = nil
        }
    }
}

enum AirPodsSystemControlError: Error {
    case routeChanged, unavailable, unconfirmed
}

/// Pure selection rules shared by discovery, writes and regression fixtures.
enum AirPodsSystemControlRules {
    static func targetIsCurrent(_ target: PanelAudioDeviceID, name: String,
                                devices: [AudioOutputDevice], paired: [(address: String, name: String)]) -> Bool {
        guard let uid = target.uid,
              let address = HuaweiAudioEndpointMatcher.bluetoothAddress(in: uid),
              paired.filter({ BluetoothBatteryReader.normalizedAddress($0.address) == address }).count == 1,
              !paired.contains(where: { $0.name == name && BluetoothBatteryReader.normalizedAddress($0.address) != address }),
              devices.filter({ $0.name == name }).count == 1 else { return false }
        return devices.contains {
            $0.id == target.id && $0.uid == uid && $0.name == name && $0.isCurrent
                && $0.isBluetoothAudio && AirPodsModel(modelUID: $0.modelUID) != nil
        }
    }

}

/// AACP control records documented by LibrePods. Ignore unknown settings and
/// incomplete records; a successful transport write is not device confirmation.
enum AirPodsControlPacket {
    static func command(_ setting: UInt8, value: UInt8) -> [UInt8]? {
        guard (setting == 0x2e && value <= 100) || (setting == 0x28 && (1...2).contains(value)) else { return nil }
        return [4, 0, 4, 0, 9, 0, setting, value, 0, 0, 0]
    }

    static func values(in data: Data) -> [UInt8: UInt8] {
        let bytes = Array(data)
        guard bytes.count >= 11 else { return [:] }
        var values: [UInt8: UInt8] = [:]
        for start in 0...(bytes.count - 11) {
            let setting = bytes[start + 6], value = bytes[start + 7]
            if let expected = command(setting, value: value), Array(bytes[start..<start + 11]) == expected {
                values[setting] = value
            }
        }
        return values
    }
}

/// A disclosure-owned control channel. Never reconnects the headset, scans, or
/// opens another app. Existing CoreAudio listening-mode control is independent.
@MainActor
final class AirPodsSystemControls: NSObject, IOBluetoothL2CAPChannelDelegate {
    enum Group { case conversation, spatial }
    private let target: PanelAudioDeviceID
    private let name: String
    private var channel: IOBluetoothL2CAPChannel?
    private var openStatus: IOReturn?
    private var values: [UInt8: UInt8] = [:]
    private var generation = 0
    private var helperConversation: Bool?
    private var spatialState: AirPodsSpatialControls.State?
    private let localization = Localization()

    init(target: PanelAudioDeviceID, name: String) {
        self.target = target
        self.name = name
    }

    func stop() {
        helperConversation = nil
        spatialState = nil
        closeChannel()
    }

    private func closeChannel() {
        generation += 1
        let old = channel
        channel = nil
        old?.setDelegate(nil)
        old?.close()
        values = [:]
        openStatus = nil
    }

    private func device() throws -> IOBluetoothDevice {
        try Task.checkCancellation()
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let identities = paired.compactMap { device -> (address: String, name: String)? in
            guard let address = device.addressString else { return nil }
            return (address, device.name ?? "")
        }
        guard AirPodsSystemControlRules.targetIsCurrent(target, name: name,
            devices: CoreAudioOutputController().outputDevices(), paired: identities),
            let uid = target.uid, let address = HuaweiAudioEndpointMatcher.bluetoothAddress(in: uid),
            let device = paired.first(where: { BluetoothBatteryReader.normalizedAddress($0.addressString ?? "") == address }),
            device.isConnected() else { throw AirPodsSystemControlError.routeChanged }
        return device
    }

    private func checkpoint(_ token: Int) throws {
        _ = try device()
        guard token == generation else { throw CancellationError() }
    }

    private func connect() async throws {
        let device = try device()
        if channel != nil, openStatus == kIOReturnSuccess { return }
        closeChannel()
        let token = generation
        var candidate: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&candidate, withPSM: 0x1001, delegate: self)
        channel = candidate
        guard status == kIOReturnSuccess, candidate != nil else { closeChannel(); throw AirPodsSystemControlError.unavailable }
        do {
            for _ in 0..<40 {
                try checkpoint(token)
                if let openStatus {
                    guard openStatus == kIOReturnSuccess else { throw AirPodsSystemControlError.unavailable }
                    try send([0,0,4,0,1,0,2,0,0,0,0,0,0x10,0,0,0])
                    try await Task.sleep(for: .milliseconds(100))
                    try checkpoint(token)
                    try send([4,0,4,0,0x0f,0,0xff,0xff,0xff,0xff])
                    return
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw AirPodsSystemControlError.unavailable
        } catch {
            if token == generation { closeChannel() }
            throw error
        }
    }

    private func send(_ bytes: [UInt8]) throws {
        _ = try device()
        guard let channel, openStatus == kIOReturnSuccess else { throw AirPodsSystemControlError.unavailable }
        var buffer = bytes
        let status = buffer.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16(bytes.count)) }
        guard status == kIOReturnSuccess else { throw AirPodsSystemControlError.unavailable }
    }

    func read(onUpdate: (AirPodsSystemSnapshot) -> Void = { _ in }) async throws -> AirPodsSystemSnapshot {
        _ = try device()
        var snapshot = AirPodsSystemSnapshot()
        let modelUID = CoreAudioOutputController().outputDevices().first { $0.id == target.id }?.modelUID
        let support = AirPodsFeatureSupport(modelUID: modelUID)
        snapshot.supportsSpatial = support.spatial
        snapshot.supportsConversation = support.conversation
        spatialState = try? AirPodsSpatialControls(deviceID: target.id).read()
        snapshot.spatial = spatialOptions()
        snapshot.spatialLoaded = true
        onUpdate(snapshot)
        let helper = try? await AirPodsAudioHelper.run(uid: target.uid ?? "")
        try Task.checkCancellation()
        _ = try device()
        helperConversation = helper?.conversation
        if let supported = helper?.conversationSupported { snapshot.supportsConversation = supported }
        snapshot.conversation = conversationOptions()
        snapshot.conversationLoaded = true
        onUpdate(snapshot)
        // The helper and Bluetooth are independent capabilities. A refused AACP
        // connection must not discard a verified Conversation Awareness read.
        do {
            try await connect()
            let token = generation
            for _ in 0..<40 {
                try checkpoint(token)
                if values[0x2e] != nil && (helper?.conversation != nil || values[0x28] != nil) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch is CancellationError { throw CancellationError() }
        catch { _ = try device() }
        snapshot.loaded = true
        snapshot.adaptive = values[0x2e].map(Int.init)
        snapshot.conversation = conversationOptions()
        return snapshot
    }

    private func conversationOptions() -> [AirPodsSystemOption] {
        guard let value = helperConversation.map({ $0 ? UInt8(1) : UInt8(2) }) ?? values[0x28] else { return [] }
        return [.init(title: localization.string(.bluetoothListeningModeOff), selected: value == 2, symbol: "person.wave.2.fill", dimWaves: true),
                .init(title: localization.string(.batteryDetailsOn), selected: value == 1, symbol: "person.wave.2.fill")]
    }

    func readSpatial() throws -> [AirPodsSystemOption] {
        _ = try device()
        spatialState = try? AirPodsSpatialControls(deviceID: target.id).read()
        return spatialOptions()
    }

    private func spatialOptions() -> [AirPodsSystemOption] {
        guard let spatialState else { return [] }
        return zip(AirPodsSpatialState.Mode.allCases,
                   [LocalizationKey.bluetoothListeningModeOff, .airPodsSpatialFixed, .airPodsSpatialHeadTracked])
            .map { mode, key in
                .init(title: localization.string(key), selected: spatialState.mode == mode,
                      symbol: mode == .headTracked ? "spatialize-stereo-head-tracked" : "person.spatialaudio.stereo.fill",
                      dimWaves: mode == .off)
            }
    }

    func select(_ title: String, group: Group) async throws -> [AirPodsSystemOption] {
        if group == .spatial {
            guard let expected = spatialState, let index = spatialOptions().firstIndex(where: { $0.title == title }) else {
                throw AirPodsSystemControlError.unavailable
            }
            spatialState = try await AirPodsSpatialControls(deviceID: target.id).set(
                AirPodsSpatialState.Mode.allCases[index], expected: expected) { _ = try self.device() }
            return spatialOptions()
        }
        guard group == .conversation, let index = conversationOptions().firstIndex(where: { $0.title == title }) else {
            throw AirPodsSystemControlError.unavailable
        }
        if helperConversation != nil {
            _ = try device()
            let result = try await AirPodsAudioHelper.run(uid: target.uid ?? "", conversation: index == 1)
            _ = try device()
            guard result.conversation == (index == 1) else { throw AirPodsSystemControlError.unconfirmed }
            helperConversation = result.conversation
        } else {
            _ = try await write(0x28, value: index == 0 ? 2 : 1)
        }
        return conversationOptions()
    }

    func setAdaptive(_ value: Int) async throws -> Int {
        guard (0...100).contains(value), value.isMultiple(of: 10) else { throw AirPodsSystemControlError.unavailable }
        return Int(try await write(0x2e, value: UInt8(value)))
    }

    private func write(_ setting: UInt8, value: UInt8) async throws -> UInt8 {
        _ = try device()
        guard values[setting] != nil, let command = AirPodsControlPacket.command(setting, value: value) else {
            throw AirPodsSystemControlError.unavailable
        }
        let token = generation
        values[setting] = nil
        try send(command)
        for _ in 0..<40 {
            try checkpoint(token)
            if values[setting] == value { return value }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AirPodsSystemControlError.unconfirmed
    }

    nonisolated func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        guard let channel else { return }
        let identity = ObjectIdentifier(channel)
        Task { @MainActor [weak self] in
            guard let self, let current = self.channel, ObjectIdentifier(current) == identity else { return }
            self.openStatus = error
        }
    }

    nonisolated func l2capChannelData(_ channel: IOBluetoothL2CAPChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard let channel, let pointer, length > 0, length <= 65535 else { return }
        let identity = ObjectIdentifier(channel)
        let data = Data(bytes: pointer, count: length)
        Task { @MainActor [weak self] in
            guard let self, let current = self.channel, ObjectIdentifier(current) == identity else { return }
            self.values.merge(AirPodsControlPacket.values(in: data)) { _, new in new }
        }
    }

    nonisolated func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
        guard let channel else { return }
        let identity = ObjectIdentifier(channel)
        Task { @MainActor [weak self] in
            guard let self, let current = self.channel, ObjectIdentifier(current) == identity else { return }
            self.closeChannel()
        }
    }
}
