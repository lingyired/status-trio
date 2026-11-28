import CoreFoundation
import Foundation

/// Reads the system-wide `GPU Energy` channel from IOReport's `Energy Model`
/// group. Symbols are loaded with `dlopen`/`dlsym`, so a missing private symbol
/// degrades to CPU-only instead of preventing app launch.
final class GPUEnergyReader: @unchecked Sendable {
    private typealias CopyChannelsInGroupFunction =
        @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubscriptionFunction =
        @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary,
                        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
                        UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias CreateSamplesFunction =
        @convention(c) (CFTypeRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelStringFunction =
        @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleValueFunction =
        @convention(c) (CFDictionary, UnsafeMutablePointer<Int32>?) -> Int64

    private struct Symbols {
        let copyChannelsInGroup: CopyChannelsInGroupFunction
        let createSubscription: CreateSubscriptionFunction
        let createSamples: CreateSamplesFunction
        let channelGetGroup: ChannelStringFunction
        let channelGetChannelName: ChannelStringFunction
        let channelGetUnitLabel: ChannelStringFunction
        let simpleGetIntegerValue: SimpleValueFunction
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        guard let copyChannels = symbol("IOReportCopyChannelsInGroup",
                                        as: CopyChannelsInGroupFunction.self),
              let createSubscription = symbol("IOReportCreateSubscription",
                                              as: CreateSubscriptionFunction.self),
              let createSamples = symbol("IOReportCreateSamples",
                                         as: CreateSamplesFunction.self),
              let getGroup = symbol("IOReportChannelGetGroup",
                                    as: ChannelStringFunction.self),
              let getChannelName = symbol("IOReportChannelGetChannelName",
                                          as: ChannelStringFunction.self),
              let getUnitLabel = symbol("IOReportChannelGetUnitLabel",
                                        as: ChannelStringFunction.self),
              let getInteger = symbol("IOReportSimpleGetIntegerValue",
                                      as: SimpleValueFunction.self) else {
            return nil
        }
        return Symbols(copyChannelsInGroup: copyChannels,
                       createSubscription: createSubscription,
                       createSamples: createSamples,
                       channelGetGroup: getGroup,
                       channelGetChannelName: getChannelName,
                       channelGetUnitLabel: getUnitLabel,
                       simpleGetIntegerValue: getInteger)
    }()

    static var isSupported: Bool { symbols != nil }

    struct ChannelReading: Equatable, Sendable {
        let group: String
        let name: String
        let unitLabel: String
        let value: Int64
    }

    /// Pure combination step, kept separate from IOReport so unit and failure
    /// cases can be tested without hardware.
    static func combine(_ readings: [ChannelReading],
                        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime)
        -> GPUEnergyReading? {
        var totalRaw: UInt64 = 0
        var commonUnit: GPUEnergyUnit?
        var sawChannel = false
        for reading in readings {
            guard reading.group == "Energy Model" else { continue }
            guard reading.name == "GPU Energy" || reading.name.hasPrefix("GPU Energy ") else { continue }
            guard let unit = GPUEnergyUnit.parse(reading.unitLabel),
                  reading.value >= 0 else { return nil }
            if let commonUnit, commonUnit != unit { return nil }
            commonUnit = unit
            totalRaw &+= UInt64(reading.value)
            sawChannel = true
        }
        guard sawChannel, let commonUnit else { return nil }
        return GPUEnergyReading(rawValue: totalRaw,
                                unit: commonUnit,
                                joules: commonUnit.joules(for: totalRaw),
                                readAt: uptime)
    }

    private var subscription: CFTypeRef?
    private var channels: CFMutableDictionary?
    private var setupFailed = false
    private var lastReading: GPUEnergyReading?

    func reset() {
        channels = nil
        subscription = nil
        setupFailed = false
        lastReading = nil
    }

    deinit { reset() }

    func read(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GPUEnergyReading? {
        guard let symbols = Self.symbols, ensureReady(symbols),
              let subscription, let channels,
              let sample = symbols.createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return nil
        }
        if let reading = Self.readGPUChannel(from: sample, symbols: symbols, at: uptime) {
            lastReading = reading
            return reading
        }
        return nil
    }

    private func ensureReady(_ symbols: Symbols) -> Bool {
        if subscription != nil { return true }
        guard !setupFailed else { return false }

        guard let channels = symbols.copyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?
            .takeRetainedValue() else {
            setupFailed = true
            return false
        }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let rawSubscription = symbols.createSubscription(nil, channels, &subscribed, 0, nil) else {
            subscribed?.release()
            setupFailed = true
            return false
        }
        subscribed?.release()
        self.channels = channels
        subscription = rawSubscription.takeRetainedValue()
        return true
    }

    private static func readGPUChannel(from sample: CFDictionary,
                                       symbols: Symbols,
                                       at uptime: TimeInterval) -> GPUEnergyReading? {
        guard let list = (sample as NSDictionary)["IOReportChannels"] as? NSArray else {
            return nil
        }
        let array = list as CFArray
        var readings: [ChannelReading] = []
        for index in 0..<CFArrayGetCount(array) {
            let channel = unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: CFDictionary.self)
            readings.append(ChannelReading(
                group: symbols.channelGetGroup(channel)?.takeUnretainedValue() as String? ?? "",
                name: symbols.channelGetChannelName(channel)?.takeUnretainedValue() as String? ?? "",
                unitLabel: symbols.channelGetUnitLabel(channel)?.takeUnretainedValue() as String? ?? "",
                value: symbols.simpleGetIntegerValue(channel, nil)
            ))
        }
        return combine(readings, at: uptime)
    }
}
