import DDCPrivateAPI
import Foundation
import IOKit
import os

let ddcTargetLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "DDCTarget"
)

/// Short, process-local id so a tester's log lines can be correlated without
/// recording any stable device identity. Regenerated every launch on purpose.
enum DDCLogSession {
    static let id = String(UInt16.random(in: 0...UInt16.max), radix: 16)
}

// IORegistry and I2C details adapted from AppleSiliconDDC revision
// 67ff964ab8123d9d35fadf7d8e1a7c677d31da14, Copyright © 2021 Istvan T. (MIT).

/// An IOKit service retained for use and release on the serial DDC worker only.
/// This type intentionally does not conform to Sendable.
final class DDCDisplayTarget {
    let uid: String
    let service: IOAVService?
    /// The read profile that produced a validated reply for this service.
    /// Nil means "not yet proven", never "assume the legacy profile".
    var readProfile: DDCReadProfile?
    /// Bounded probe pacing for this service; reset whenever a probe runs.
    var readsSinceLastProbe = DDCReadProfilePolicy.readsBetweenProbes
    /// Last reply/problem shape logged, so steady state does not spam.
    var lastLoggedKind: String?

    init(uid: String, service: IOAVService?) {
        self.uid = uid
        self.service = service
    }
}

protocol DDCVolumeTransport: AnyObject {
    func resolve(uid: String) -> DDCDisplayTarget?
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult
    /// `true` means the I2C write was acknowledged. It is not proof that the
    /// display applied the value; only a read-back can say that.
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool
}

/// Direct DDC access for external Apple Silicon displays.
/// Construct and call this transport on its owning serial worker queue.
final class DDCDisplayTransport: DDCVolumeTransport {
    private static let chipAddress = DDCPacket.chipAddress
    private static let dataAddress = DDCPacket.dataAddress
    private static let volumeVCP = DDCPacket.volumeVCP

    static func isConnectedExternalFramebuffer(
        ioNameMatched: String?,
        displayWidth: Int?,
        displayHeight: Int?
    ) -> Bool {
        guard let ioNameMatched,
              ioNameMatched.hasPrefix("dispext"),
              let displayWidth,
              let displayHeight else { return false }
        return displayWidth > 0 && displayHeight > 0
    }

    /// Maps `IONameMatched` ("dispext0,t603x") to the branch token shared with
    /// the owning DCP branch ("dispext0"). Returns nil for anything that is not
    /// a numbered `dispextN` branch, which keeps matching strict.
    static func branchToken(fromIONameMatched name: String?) -> String? {
        guard let name else { return nil }
        let token = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
        return isExternalBranchToken(token) ? token : nil
    }

    static func isExternalBranchToken(_ token: String) -> Bool {
        let prefix = "dispext"
        guard token.hasPrefix(prefix) else { return false }
        let suffix = token.dropFirst(prefix.count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    /// Extracts the branch token an external DCP AV service proxy belongs to.
    ///
    /// Real Apple Silicon firmware registers the proxy's ancestor as
    /// `dispextN:dcpav-service-epic:U` under the matching `dcpextN` branch, so
    /// the token comes from the registry name itself rather than from
    /// enumeration order.
    static func branchToken(fromServiceAncestorNames names: [String]) -> String? {
        for name in names {
            guard let separator = name.firstIndex(of: ":") else { continue }
            let token = String(name[name.startIndex..<separator])
            let role = String(name[name.index(after: separator)...])
            guard isExternalBranchToken(token), role.hasPrefix("dcpav-service-epic") else { continue }
            return token
        }
        return nil
    }

    func resolve(uid: String) -> DDCDisplayTarget? {
        #if arch(arm64)
        guard !uid.isEmpty else {
            logUnavailable(.missingAudioUID, framebuffers: 0, services: 0)
            return nil
        }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            logUnavailable(.transportUnavailable, framebuffers: 0, services: 0)
            return nil
        }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            logUnavailable(.transportUnavailable, framebuffers: 0, services: 0)
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var framebuffers: [DDCFramebufferSnapshot] = []
        var services: [(entryID: UInt64, snapshot: DDCServiceSnapshot, entry: io_service_t)] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            switch Self.registryName(entry) {
            case "IOMobileFramebufferShim":
                let ioNameMatched = Self.stringProperty("IONameMatched", entry: entry)
                let displayWidth = Self.integerProperty("DisplayWidth", entry: entry)
                let displayHeight = Self.integerProperty("DisplayHeight", entry: entry)
                if Self.isConnectedExternalFramebuffer(
                    ioNameMatched: ioNameMatched,
                    displayWidth: displayWidth,
                    displayHeight: displayHeight
                ), let branchToken = Self.branchToken(fromIONameMatched: ioNameMatched),
                   let entryID = Self.registryEntryID(entry) {
                    framebuffers.append(DDCFramebufferSnapshot(
                        entryID: entryID,
                        branchName: branchToken,
                        edidUUID: Self.stringProperty("EDID UUID", entry: entry, recursive: true)
                    ))
                }
                IOObjectRelease(entry)
            case "DCPAVServiceProxy" where Self.stringProperty("Location", entry: entry) == "External":
                if let entryID = Self.registryEntryID(entry) {
                    services.append((
                        entryID: entryID,
                        snapshot: DDCServiceSnapshot(
                            entryID: entryID,
                            branchName: Self.branchToken(fromServiceAncestorNames: Self.ancestorNames(of: entry)),
                            location: "External"
                        ),
                        entry: entry
                    ))
                } else {
                    IOObjectRelease(entry)
                }
            default:
                IOObjectRelease(entry)
            }
        }
        defer { services.forEach { _ = IOObjectRelease($0.entry) } }

        let resolution = DDCTargetResolver.resolve(
            outputUID: uid,
            framebuffers: framebuffers,
            services: services.map(\.snapshot)
        )
        let selected = DDCTargetResolver.openResolvedTarget(
            resolution,
            services: services.map { (entryID: $0.entryID, handle: $0.entry) }
        ) { entry in
            IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
        }
        guard let selected else {
            logFailure(resolution, framebuffers: framebuffers.count, services: services.count)
            return nil
        }
        let target = selected.opened
        if let branchName = services.first(where: { $0.entryID == selected.serviceEntryID })?.snapshot.branchName {
            ddcTargetLogger.notice(
                "ddc.resolve result=matched branch=\(branchName, privacy: .public) framebuffers=\(framebuffers.count, privacy: .public) services=\(services.count, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
            )
        } else {
            ddcTargetLogger.notice(
                "ddc.resolve result=matched path=legacySingleDisplay framebuffers=\(framebuffers.count, privacy: .public) services=\(services.count, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
            )
        }
        return DDCDisplayTarget(uid: uid, service: target)
        #else
        logUnavailable(.unsupportedArchitecture, framebuffers: 0, services: 0)
        return nil
        #endif
    }

    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        #if arch(arm64)
        guard let service = target.service else { return .failure(.serviceUnavailable) }

        // A proven profile is reused for every later poll of this same service.
        if let profile = target.readProfile {
            let result = verifiedRead(service: service, profile: profile, target: target)
            if let failure = result.failureReason {
                logReadFailureIfChanged(failure: failure, profile: profile, target: target)
            }
            return result
        }

        target.readsSinceLastProbe += 1
        guard DDCReadProfilePolicy.shouldRunProbe(
            cachedProfile: nil,
            readsSinceLastProbe: target.readsSinceLastProbe
        ) else { return .failure(.replyReadFailed) }
        target.readsSinceLastProbe = 0

        let started = DispatchTime.now()
        var isFirstCandidate = true
        let selection = DDCReadProfileProbe.select { profile in
            // 50-100 ms of bus idle time between independent candidates.
            if !isFirstCandidate { usleep(75_000) }
            isFirstCandidate = false
            return probeOutcome(service: service, profile: profile)
        }
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds &- started.uptimeNanoseconds) / 1_000_000)
        for attempt in selection.attempts {
            ddcTargetLogger.info(
                "ddc.probe profile=\(attempt.profile.label, privacy: .public) stage=\(attempt.outcome.diagnosticStage, privacy: .public) outcome=\(attempt.outcome.diagnosticName, privacy: .public) attempts=\(selection.attempts.count, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
            )
        }

        if let profile = selection.profile, let reply = selection.reply {
            target.readProfile = profile
            target.lastLoggedKind = nil
            ddcTargetLogger.notice(
                "ddc.selectedProfile profile=\(profile.label, privacy: .public) result=usable stage=validate elapsedMs=\(elapsedMs, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
            )
            return .reply(reply)
        }

        let failure = selection.failure ?? .replyReadFailed
        target.lastLoggedKind = failure.diagnosticName
        ddcTargetLogger.notice(
            "ddc.selectedProfile result=unavailable stage=\(failure.diagnosticStage, privacy: .public) reason=\(failure.diagnosticName, privacy: .public) attempts=\(selection.attempts.count, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
        )
        return .failure(failure)
        #else
        return .failure(.serviceUnavailable)
        #endif
    }

    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        #if arch(arm64)
        // Writing is only allowed on a service whose read path was proven.
        guard let service = target.service, target.readProfile != nil else { return false }
        let packet = DDCPacket.setVCPRequest(value: value)
        var succeeded = false
        for attempt in 0..<5 {
            for _ in 0..<2 {
                usleep(attempt == 0 ? 10_000 : 20_000)
                var mutablePacket = packet
                succeeded = mutablePacket.withUnsafeMutableBytes {
                    IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count)) == kIOReturnSuccess
                }
            }
            if succeeded { break }
        }
        ddcTargetLogger.notice(
            "ddc.write stage=set result=\(succeeded ? "acknowledged" : "failed", privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
        )
        return succeeded
        #else
        return false
        #endif
    }

    #if arch(arm64)
    /// Which half of one Get VCP exchange failed, so diagnostics never collapse
    /// "the host could not send" and "the display did not answer".
    private enum ExchangeResult {
        case bytes([UInt8])
        case requestWriteFailed
        case replyReadFailed
    }

    /// One Get VCP exchange for a specific profile, without classification.
    private func exchangeOnce(service: IOAVService, profile: DDCReadProfile, delayMicroseconds: UInt32) -> ExchangeResult {
        usleep(delayMicroseconds)
        var packet = DDCPacket.getVCPRequest(checksumMode: profile.checksumMode)
        let writeResult = packet.withUnsafeMutableBytes {
            IOAVServiceWriteI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress, UInt32($0.count))
        }
        guard writeResult == kIOReturnSuccess else { return .requestWriteFailed }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        let readResult = reply.withUnsafeMutableBytes {
            IOAVServiceReadI2C(service, Self.chipAddress, profile.readAddress, $0.baseAddress, UInt32($0.count))
        }
        guard readResult == kIOReturnSuccess else { return .replyReadFailed }
        // A successful read that never filled the buffer classifies as `.zeros`
        // and is rejected by validation; success alone proves nothing.
        return .bytes(reply)
    }

    /// Bounded per-candidate probe: at most two attempts, then move on.
    private func probeOutcome(service: IOAVService, profile: DDCReadProfile) -> DDCProbeOutcome {
        var lastOutcome: DDCProbeOutcome?
        for attempt in 0..<2 {
            switch exchangeOnce(service: service, profile: profile, delayMicroseconds: attempt == 0 ? 10_000 : 20_000) {
            case .bytes(let bytes):
                let kind = DDCVolumeReply.classify(bytes)
                if case .valid = kind { return .reply(kind) }
                lastOutcome = .reply(kind)
            case .requestWriteFailed:
                lastOutcome = .requestWriteFailed
            case .replyReadFailed:
                lastOutcome = .replyReadFailed
            }
        }
        return lastOutcome ?? .replyReadFailed
    }

    /// Steady-state read on an already-proven profile, keeping the previous
    /// five-attempt retry budget.
    private func verifiedRead(service: IOAVService, profile: DDCReadProfile, target: DDCDisplayTarget) -> DDCVolumeReadResult {
        var lastFailure: DDCReadFailure = .replyReadFailed
        for attempt in 0..<5 {
            switch exchangeOnce(service: service, profile: profile, delayMicroseconds: attempt == 0 ? 10_000 : 20_000) {
            case .bytes(let bytes):
                let kind = DDCVolumeReply.classify(bytes)
                switch kind {
                case .valid(let reply):
                    target.lastLoggedKind = nil
                    return .reply(reply)
                case .vcpRefused:
                    lastFailure = .vcpRejected
                default:
                    lastFailure = .replyRejected(kind)
                }
            case .requestWriteFailed:
                lastFailure = .requestWriteFailed
            case .replyReadFailed:
                lastFailure = .replyReadFailed
            }
        }
        return .failure(lastFailure)
    }

    /// One log line per distinct steady-state failure shape, not per poll.
    private func logReadFailureIfChanged(failure: DDCReadFailure, profile: DDCReadProfile, target: DDCDisplayTarget) {
        guard target.lastLoggedKind != failure.diagnosticName else { return }
        target.lastLoggedKind = failure.diagnosticName
        ddcTargetLogger.notice(
            "ddc.read result=unavailable stage=\(failure.diagnosticStage, privacy: .public) reason=\(failure.diagnosticName, privacy: .public) profile=\(profile.label, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
        )
    }
    #endif

    #if arch(arm64)
    private static func registryEntryID(_ entry: io_registry_entry_t) -> UInt64? {
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS, identifier != 0 else { return nil }
        return identifier
    }

    /// Ancestor entry names on the IOService plane, nearest first.
    private static func ancestorNames(of entry: io_registry_entry_t, limit: Int = 8) -> [String] {
        var names: [String] = []
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<limit {
            var parent: io_registry_entry_t = IO_OBJECT_NULL
            guard IORegistryEntryGetParentEntry(current, "IOService", &parent) == KERN_SUCCESS,
                  parent != IO_OBJECT_NULL else { break }
            if let name = registryName(parent) { names.append(name) }
            IOObjectRelease(current)
            current = parent
        }
        return names
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String? {
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return nil }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func stringProperty(_ key: String, entry: io_registry_entry_t, recursive: Bool = false) -> String? {
        let options = recursive ? IOOptionBits(kIORegistryIterateRecursively) : 0
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, options)?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func integerProperty(_ key: String, entry: io_registry_entry_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return value as? Int
    }
    #endif

    private func logFailure(_ resolution: DDCResolution, framebuffers: Int, services: Int) {
        let reason: DDCResolutionFailure = switch resolution {
        case .unavailable(let failure): failure
        case .matched: .transportUnavailable
        }
        logUnavailable(reason, framebuffers: framebuffers, services: services)
    }

    private func logUnavailable(_ failure: DDCResolutionFailure, framebuffers: Int, services: Int) {
        ddcTargetLogger.notice(
            "ddc.resolve result=unavailable stage=resolve reason=\(failure.diagnosticName, privacy: .public) framebuffers=\(framebuffers, privacy: .public) services=\(services, privacy: .public) session=\(DDCLogSession.id, privacy: .public)"
        )
    }
}
