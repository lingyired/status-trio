import Darwin
import Foundation

protocol ApplicationEnergyReading: Sendable {
    func read(applications: [ProcessApplication]) -> ApplicationEnergySnapshot
    func reset()
}

/// Ordinary-user process energy reader. It never launches powermetrics, asks
/// for root or reads process memory. CPU energy comes from `RUSAGE_INFO_V6`;
/// GPU client time comes from the non-privileged IOAccelerator registry and GPU
/// total energy from IOReport's `Energy Model` group.
final class ApplicationEnergyReader: ApplicationEnergyReading, @unchecked Sendable {
    private struct CachedMetadata {
        let startedAt: UInt64?
        let metadata: ProcessMetadata
    }

    private let gpuClientReader: ApplicationGPUClientReader
    private let gpuEnergyReader: GPUEnergyReader
    private var metadataCache: [Int32: CachedMetadata] = [:]

    init(gpuClientReader: ApplicationGPUClientReader = ApplicationGPUClientReader(),
         gpuEnergyReader: GPUEnergyReader = GPUEnergyReader()) {
        self.gpuClientReader = gpuClientReader
        self.gpuEnergyReader = gpuEnergyReader
    }

    func reset() {
        metadataCache.removeAll()
        gpuEnergyReader.reset()
    }

    func read(applications: [ProcessApplication]) -> ApplicationEnergySnapshot {
        let readAt = ProcessInfo.processInfo.systemUptime
        let processes = readProcesses(applications: applications)
        let capabilities = capabilities(for: processes)
        let gpuClients = readGPUClientSamples(applications: applications)
        let gpuEnergy = gpuEnergyReader.read(at: readAt)
        var finalCapabilities = capabilities
        if gpuEnergy != nil { finalCapabilities.insert(.gpuEnergy) }
        if GPUEnergyReader.isSupported { finalCapabilities.insert(.gpuEnergyRuntime) }
        if !gpuClients.isEmpty { finalCapabilities.insert(.gpuClients) }
        return ApplicationEnergySnapshot(
            readAt: readAt,
            processes: processes,
            gpuClients: gpuClients,
            gpuEnergy: gpuEnergy,
            capabilities: finalCapabilities
        )
    }

    private func capabilities(for processes: [ProcessEnergySample]) -> ApplicationEnergyCapabilities {
        var capabilities: ApplicationEnergyCapabilities = []
        if processes.contains(where: { $0.energyNanojoules != nil }) {
            capabilities.insert(.cpuEnergy)
        }
        if processes.contains(where: { $0.cpuNanoseconds > 0 }) {
            capabilities.insert(.cpuActivity)
        }
        return capabilities
    }

    private func readProcesses(applications: [ProcessApplication]) -> [ProcessEnergySample] {
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard bytes > 0 else { return [] }
        let capacity = min(Int(bytes) / MemoryLayout<pid_t>.stride + 64, 16_384)
        var pids = [pid_t](repeating: 0, count: capacity)
        let returned = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
        }
        let count = max(0, min(Int(returned) / MemoryLayout<pid_t>.stride, capacity))

        var processes: [ProcessEnergySample] = []
        processes.reserveCapacity(count)
        for pid in pids.prefix(count) where pid > 0 {
            guard let metadata = metadata(for: pid, fallbackName: ""),
                  let startedAt = metadata.identity.startedAt else { continue }

            var energyNanojoules: UInt64?
            var cpuNanoseconds: UInt64?
            var usage = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            if status == 0 {
                cpuNanoseconds = usage.ri_user_time &+ usage.ri_system_time
                energyNanojoules = usage.ri_energy_nj > 0 ? usage.ri_energy_nj : nil
            } else {
                // Older kernels may not implement flavor 6. Flavor 4 still
                // supplies CPU time, explicitly presented as an activity proxy.
                var fallback = rusage_info_v4()
                let result = withUnsafeMutablePointer(to: &fallback) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                    }
                }
                if result == 0 {
                    cpuNanoseconds = fallback.ri_user_time &+ fallback.ri_system_time
                }
            }
            guard let cpuNanoseconds else { continue }

            let resolution = ProcessAppResolver.resolve(
                metadata,
                applications: applications,
                parentMetadata: { [weak self] parentPID in
                    self?.metadata(for: parentPID, fallbackName: "")
                }
            )
            let app = energyApplication(from: resolution)
            processes.append(ProcessEnergySample(
                pid: pid,
                startedAt: startedAt,
                app: app,
                cpuNanoseconds: cpuNanoseconds,
                energyNanojoules: energyNanojoules,
                isApplication: resolution.isApplication
            ))
        }
        return processes
    }

    private func readGPUClientSamples(applications: [ProcessApplication]) -> [GPUClientSample] {
        switch gpuClientReader.read() {
        case .unsupported, .failed:
            return []
        case .clients(let rawClients):
            return rawClients.map { client in
                let metadata = client.pid.flatMap { metadata(for: $0, fallbackName: client.name) }
                let resolution = metadata.map {
                    ProcessAppResolver.resolve(
                        $0,
                        applications: applications,
                        parentMetadata: { [weak self] parentPID in
                            self?.metadata(for: parentPID, fallbackName: "")
                        }
                    )
                }
                let app = resolution.map { energyApplication(from: $0) }
                return GPUClientSample(
                    entryID: client.entryID,
                    pid: client.pid,
                    startedAt: metadata?.identity.startedAt,
                    name: metadata?.name ?? client.name,
                    executablePath: metadata?.executablePath,
                    responsiblePID: metadata?.responsiblePID,
                    queueCount: client.queueCount,
                    accumulatedGPUTime: client.gpuTime,
                    app: app,
                    isApplication: resolution?.isApplication ?? false
                )
            }
        }
    }

    private func energyApplication(from resolution: ProcessAppResolution) -> EnergyApplication {
        switch resolution.identity {
        case .application(let path):
            return EnergyApplication(id: path, name: resolution.name)
        case .process(let identity):
            return EnergyApplication(id: "process:\(identity.pid):\(identity.startedAt ?? 0)",
                                     name: resolution.name)
        }
    }

    /// Legacy helper retained for path-association tests: outer app bundles own
    /// nested helper bundles, while similar sibling names do not match.
    static func application(for executable: String,
                            applications: [EnergyApplication]) -> EnergyApplication? {
        applications.filter { executable.hasPrefix($0.id + "/") }
            .min { $0.id.count < $1.id.count }
    }

    /// Caches name/path/responsibility per process lifetime while always
    /// re-checking the start time, so PID reuse cannot inherit stale metadata.
    private func metadata(for pid: Int32, fallbackName: String) -> ProcessMetadata? {
        guard pid > 0 else { return nil }
        let startedAt = SystemProcessMetadataReader.startTime(for: pid)
        if let cached = metadataCache[pid], cached.startedAt == startedAt {
            return cached.metadata
        }
        guard let metadata = SystemProcessMetadataReader().metadata(for: pid,
                                                                    fallbackName: fallbackName) else {
            return nil
        }
        if metadataCache.count > 4_096 {
            metadataCache.removeAll(keepingCapacity: true)
        }
        metadataCache[pid] = CachedMetadata(startedAt: metadata.identity.startedAt,
                                            metadata: metadata)
        return metadata
    }
}
