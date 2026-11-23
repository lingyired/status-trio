import AppKit
import CoreAudio

/// Current BTAudio ABI: UInt32 saved mode, one head-tracking byte, padding.
/// Saved Automatic/Multichannel Only do not imply that stereo is spatialized.
enum AirPodsSpatialState {
    enum Mode: CaseIterable { case off, fixed, headTracked }

    static func mode(configuration: [UInt8], active: Bool) -> Mode? {
        guard configuration.count == 8, configuration[0] <= 3,
              configuration[1...3].allSatisfy({ $0 == 0 }), configuration[4] <= 1 else { return nil }
        guard active else { return .off }
        return configuration[4] == 1 ? .headTracked : .fixed
    }

    static func command(_ mode: Mode, pid: UInt32) -> [UInt8]? {
        guard pid > 0, pid <= UInt32(Int32.max) else { return nil }
        return withUnsafeBytes(of: pid.littleEndian) { Array($0) }
            + [mode == .headTracked ? 1 : 0, mode == .off ? 0 : 1, 0, 0]
    }
}

/// Short-lived, current-client CoreAudio access. No player activation, routing,
/// preferences writes, reconnects, or UI automation.
@MainActor
struct AirPodsSpatialControls {
    struct State {
        let pid: UInt32
        let bundleID: String
        let mode: AirPodsSpatialState.Mode
    }
    let deviceID: AudioDeviceID

    private func integer(_ selector: UInt32) throws -> UInt32 {
        var address = BluetoothListeningModeProperty.address(selector)
        var value: UInt32 = 0, size: UInt32 = 4
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              size == 4 else { throw AirPodsSystemControlError.unavailable }
        return value
    }

    func read() throws -> State {
        try Task.checkCancellation()
        guard try integer(0x73706176) == 1 else { throw AirPodsSystemControlError.unavailable } // spav
        let pid = try integer(0x61637363) // acsc
        guard pid > 0, pid <= UInt32(Int32.max),
              let bundleID = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier else {
            throw AirPodsSystemControlError.unavailable
        }
        var address = BluetoothListeningModeProperty.address(0x73706366) // spcf
        let bundle = bundleID as CFString
        var qualifier = Unmanaged.passUnretained(bundle).toOpaque()
        var size: UInt32 = 8
        var configuration = [UInt8](repeating: 0, count: 8)
        let status = withExtendedLifetime(bundle) { configuration.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(deviceID, &address, UInt32(MemoryLayout.size(ofValue: qualifier)),
                                       &qualifier, &size, $0.baseAddress!)
        } }
        let spatial = try integer(0x73706373), stereo = try integer(0x73707373)
        guard status == noErr, size == 8, spatial <= 1, stereo <= 1,
              let mode = AirPodsSpatialState.mode(configuration: configuration, active: spatial == 1 || stereo == 1),
              try integer(0x61637363) == pid else { throw AirPodsSystemControlError.unavailable }
        return State(pid: pid, bundleID: bundleID, mode: mode)
    }

    func set(_ mode: AirPodsSpatialState.Mode, expected: State,
             validateRoute: () throws -> Void) async throws -> State {
        try validateRoute()
        let before = try read()
        guard before.pid == expected.pid, before.bundleID == expected.bundleID else {
            throw AirPodsSystemControlError.routeChanged
        }
        guard let bytes = AirPodsSpatialState.command(mode, pid: before.pid) else {
            throw AirPodsSystemControlError.unavailable
        }
        // AirBuddy uses both multichannel and stereo control paths. These carry
        // the same desired flags, so the driver's coalescing cannot invert them.
        for selector: UInt32 in [0x73706373, 0x73707373] {
            try Task.checkCancellation()
            try validateRoute()
            guard try integer(0x61637363) == before.pid else { throw AirPodsSystemControlError.routeChanged }
            var address = BluetoothListeningModeProperty.address(selector)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue else {
                throw AirPodsSystemControlError.unavailable
            }
            let status = bytes.withUnsafeBytes {
                AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(bytes.count), $0.baseAddress!)
            }
            guard status == noErr else { throw AirPodsSystemControlError.unavailable }
        }
        // BTAudio can acknowledge before the media engine updates, and ignores
        // overlapping transitions for five seconds. Keep this operation busy
        // through that interval instead of accepting a stale instantaneous read.
        var result: State?
        for _ in 0..<24 {
            try await Task.sleep(for: .milliseconds(250))
            try validateRoute()
            let state = try read()
            guard state.pid == before.pid, state.bundleID == before.bundleID else {
                throw AirPodsSystemControlError.routeChanged
            }
            result = state
        }
        guard let result, result.mode == mode else { throw AirPodsSystemControlError.unconfirmed }
        return result
    }
}
