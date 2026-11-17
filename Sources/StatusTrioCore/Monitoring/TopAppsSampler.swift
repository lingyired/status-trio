import Foundation

protocol TopAppsSampling: Sendable {
    func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult
    func reset() async
}

/// Owns every reader and both cumulative trackers. One instance serializes its
/// own state; the service above it guarantees only one read is in flight.
actor TopAppsSampler: TopAppsSampling {
    private let cpuReader: TopAppCPUReader
    private let memoryReader: TopAppMemoryReader
    private let networkReader: TopAppNetworkReader
    private let gpuReader: TopAppGPUReader
    private let clock: @Sendable () -> UInt64
    private let gpuQueue = DispatchQueue(label: "StatusTrio.TopApps.GPU", qos: .utility)
    private var networkTracker = NetworkAppUsageTracker()
    private var gpuTracker = GPUAppUsageTracker()
    private var lastMetric: TopAppMetric?

    init(executor: any TopAppCommandExecuting = SystemTopAppCommandExecutor(),
         metadataReader: any ProcessMetadataReading = SystemProcessMetadataReader(),
         gpuReader: TopAppGPUReader? = nil,
         clock: @escaping @Sendable () -> UInt64 = { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }) {
        self.cpuReader = TopAppCPUReader(executor: executor, metadataReader: metadataReader)
        self.memoryReader = TopAppMemoryReader(executor: executor, metadataReader: metadataReader)
        self.networkReader = TopAppNetworkReader(executor: executor, metadataReader: metadataReader)
        self.gpuReader = gpuReader ?? TopAppGPUReader(metadataReader: metadataReader)
        self.clock = clock
    }

    func reset() async {
        networkTracker.reset()
        gpuTracker.reset()
        lastMetric = nil
    }

    func read(_ metric: TopAppMetric, applications: [ProcessApplication]) async -> TopAppsReadResult {
        if lastMetric != metric {
            networkTracker.reset()
            gpuTracker.reset()
            lastMetric = metric
        }
        switch metric {
        case .cpu:
            return await aggregate(.cpu, result: cpuReader.read(), applications: applications)
        case .memory:
            return await aggregate(.memory, result: memoryReader.read(), applications: applications)
        case .network:
            switch await networkReader.read() {
            case .failure(let error):
                return error == .unsupported ? .unsupported : .failed
            case .success(let counters):
                guard let samples = networkTracker.sample(counters, at: clock()) else {
                    return .collecting
                }
                return .measured(TopAppAggregator.rows(metric: .network,
                                                        samples: samples,
                                                        applications: applications))
            }
        case .gpu:
            switch await readGPU() {
            case .failure(let error):
                return error == .unsupported ? .unsupported : .failed
            case .success(let clients):
                guard let samples = gpuTracker.sample(clients, at: clock()) else {
                    return .collecting
                }
                return .measured(TopAppAggregator.rows(metric: .gpu,
                                                        samples: samples,
                                                        applications: applications))
            }
        }
    }

    private func aggregate(_ metric: TopAppMetric,
                           result: Result<[ProcessUsageSample], TopAppReadError>,
                           applications: [ProcessApplication]) async -> TopAppsReadResult {
        switch result {
        case .failure(let error):
            return error == .unsupported ? .unsupported : .failed
        case .success(let samples):
            return .measured(TopAppAggregator.rows(metric: metric,
                                                    samples: samples,
                                                    applications: applications))
        }
    }

    private func readGPU() async -> Result<[GPUClientCounter], TopAppReadError> {
        await withCheckedContinuation { continuation in
            gpuQueue.async { [gpuReader] in
                continuation.resume(returning: gpuReader.read())
            }
        }
    }
}
