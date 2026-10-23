import Darwin
import Foundation

protocol MobileBatteryHelperExecuting: Sendable {
    func run(arguments: [String], timeout: Duration) async throws -> Data
}

enum MobileBatteryHelperError: Error, Equatable {
    case unavailable
    case timedOut
    case cancelled
    case processFailed
    case outputTooLarge
    case cycleTimedOut
}

struct ProcessMobileBatteryHelperExecutor: MobileBatteryHelperExecuting {
    private let helperURL: URL

    init(bundleURL: URL = Bundle.main.bundleURL) {
        helperURL = bundleURL.appendingPathComponent("Contents/Helpers/StatusTrioMobileBatteryHelper", isDirectory: false)
    }

    init(helperURL: URL) { self.helperURL = helperURL }

    func run(arguments: [String], timeout: Duration) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else { throw MobileBatteryHelperError.unavailable }
        let outcome = await BoundedProcessInvocation.run(
            executableURL: helperURL,
            arguments: arguments,
            timeout: timeout
        )
        switch outcome {
        case .exited(let data): return data
        case .timedOut: throw MobileBatteryHelperError.timedOut
        case .cancelled: throw MobileBatteryHelperError.cancelled
        case .failed: throw MobileBatteryHelperError.processFailed
        case .outputTooLarge: throw MobileBatteryHelperError.outputTooLarge
        }
    }
}

struct MobileBatteryHelperReader: MobileBatteryReading {
    private let executor: any MobileBatteryHelperExecuting
    private let cycleTimeout: Duration

    init(
        executor: any MobileBatteryHelperExecuting = ProcessMobileBatteryHelperExecutor(),
        cycleTimeout: Duration = .seconds(25)
    ) {
        self.executor = executor
        self.cycleTimeout = cycleTimeout
    }

    func discover() async throws -> [AppleDeviceCandidate] {
        let listingData = try await executor.run(arguments: ["--list"], timeout: .seconds(3))
        let phones = try MobileBatteryWire.decodeListing(listingData).prefix(8)
        return await withTaskGroup(of: [AppleDeviceCandidate].self, returning: [AppleDeviceCandidate].self) { group in
            for phone in phones {
                guard !Task.isCancelled else { break }
                group.addTask { await discover(phone) }
            }
            var candidates: [AppleDeviceCandidate] = []
            while let values = await group.next() {
                candidates.append(contentsOf: values)
                let merged = Self.mergeCandidates(candidates)
                if merged.count >= 8 { return Array(merged.prefix(8)) }
            }
            return Array(Self.mergeCandidates(candidates).prefix(8))
        }
    }

    func read(selectedIDs: Set<AppleDeviceID>) async throws -> MobileBatteryReadResult {
        guard !selectedIDs.isEmpty else { return MobileBatteryReadResult() }
        let accumulator = MobileBatteryReadAccumulator()
        return try await withThrowingTaskGroup(of: MobileBatteryReadResult.self) { group in
            group.addTask { try await readCycle(selectedIDs, accumulator: accumulator) }
            group.addTask {
                try await Task.sleep(for: cycleTimeout)
                throw MobileBatteryHelperError.cycleTimedOut
            }
            do {
                guard let result = try await group.next() else { return MobileBatteryReadResult() }
                group.cancelAll()
                return result
            } catch MobileBatteryHelperError.cycleTimedOut {
                group.cancelAll()
                while (try? await group.next()) != nil {}
                if Task.isCancelled { throw CancellationError() }
                var result = await accumulator.snapshot()
                result.failures.append(MobileBatteryReadFailure(category: "cycle-timeout", deviceID: nil))
                return result
            } catch {
                group.cancelAll()
                while (try? await group.next()) != nil {}
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        }
    }

    private func readCycle(_ selectedIDs: Set<AppleDeviceID>, accumulator: MobileBatteryReadAccumulator) async throws -> MobileBatteryReadResult {
        try Task.checkCancellation()
        let listingData = try await executor.run(arguments: ["--list"], timeout: .seconds(3))
        let routes = try MobileBatteryWire.decodeListing(listingData)
        let selectedPhones = Set(selectedIDs.compactMap { id -> String? in
            if case let .trustedDevice(identifier) = id { return identifier }
            return nil
        })
        let selectedWatches = selectedIDs.compactMap { id -> (String, String)? in
            if case let .trustedWatch(parentID, watchID) = id { return (parentID, watchID) }
            return nil
        }
        let requestedPhoneRoutes = Array(routes.filter { selectedPhones.contains($0.id) }.prefix(8))
        let routesByParent = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0.transports) })
        let requestedWatches = selectedWatches.compactMap { parentID, watchID -> WatchCandidate? in
            guard let transports = routesByParent[parentID], !transports.isEmpty else { return nil }
            let route = WatchRoute(id: watchID, parentID: parentID, transport: transports[0])
            return WatchCandidate(route: route, transports: transports)
        }
        let sortedWatches = requestedWatches.sorted { $0.route.parentID == $1.route.parentID
            ? $0.route.id < $1.route.id
            : $0.route.parentID < $1.route.parentID
        }.prefix(8).map { $0 }
        var jobs: [MobileBatteryHelperReadJob] = []
        let jobCount = max(requestedPhoneRoutes.count, sortedWatches.count)
        for index in 0..<jobCount {
            if index < requestedPhoneRoutes.count { jobs.append(.phone(requestedPhoneRoutes[index])) }
            if index < sortedWatches.count { jobs.append(.watch(sortedWatches[index])) }
        }
        await readJobs(jobs, accumulator: accumulator)
        return await accumulator.snapshot()
    }

    private func discover(_ phone: PhoneRoute) async -> [AppleDeviceCandidate] {
        var candidates: [AppleDeviceCandidate] = []
        for transport in phone.transports {
            do {
                let data = try await executor.run(
                    arguments: ["--discover-device", phone.id, "--transport", transport.rawValue],
                    timeout: .seconds(5)
                )
                let decoded = try MobileBatteryWire.decodeDiscovery(data, expectedParentID: phone.id)
                candidates.append(contentsOf: decoded)
                if !decoded.isEmpty { break }
            } catch {
                if Task.isCancelled { return candidates }
            }
        }
        return candidates
    }

    private func readJobs(_ jobs: [MobileBatteryHelperReadJob], accumulator: MobileBatteryReadAccumulator) async {
        await withTaskGroup(of: MobileBatteryReadResult.self) { group in
            var nextIndex = 0
            for _ in 0..<min(2, jobs.count) {
                let job = jobs[nextIndex]
                nextIndex += 1
                group.addTask { await read(job) }
            }
            while let result = await group.next() {
                await accumulator.append(result)
                if !Task.isCancelled, nextIndex < jobs.count {
                    let job = jobs[nextIndex]
                    nextIndex += 1
                    group.addTask { await read(job) }
                }
            }
        }
    }

    private func read(_ job: MobileBatteryHelperReadJob) async -> MobileBatteryReadResult {
        switch job {
        case let .phone(phone): await readPhone(phone)
        case let .watch(watch): await readWatch(watch)
        }
    }

    private func readPhone(_ phone: PhoneRoute) async -> MobileBatteryReadResult {
        var collected = MobileBatteryReadResult()
        let deadline = ContinuousClock.now + .seconds(5)
        for transport in phone.transports {
            let remainingBudget = ContinuousClock.now.duration(to: deadline)
            guard remainingBudget > .zero else { break }
            do {
                let data = try await executor.run(
                    arguments: ["--read-phone", phone.id, "--transport", transport.rawValue],
                    timeout: remainingBudget
                )
                let decoded = try MobileBatteryWire.decode(data, expectedParentID: phone.id, observedAt: Date())
                var returnedPhone = false
                for snapshot in decoded.snapshots {
                    guard snapshot.parentID == nil, snapshot.id == phone.id else {
                        collected.failures.append(MobileBatteryReadFailure(category: "unsolicited-device", deviceID: snapshot.id))
                        continue
                    }
                    collected.snapshots.append(snapshot)
                    returnedPhone = true
                }
                collected.failures.append(contentsOf: decoded.failures)
                if returnedPhone { break }
            } catch is CancellationError {
                return collected
            } catch {
                if Task.isCancelled { return collected }
                collected.failures.append(MobileBatteryReadFailure(category: "read-failed", deviceID: phone.id))
            }
        }
        return collected
    }

    private func readWatch(_ candidate: WatchCandidate) async -> MobileBatteryReadResult {
        var collected = MobileBatteryReadResult()
        let transports = candidate.transports.contains(candidate.route.transport)
            ? [candidate.route.transport] + candidate.transports.filter { $0 != candidate.route.transport }
            : candidate.transports
        let deadline = ContinuousClock.now + .seconds(5)
        for transport in transports {
            let remainingBudget = ContinuousClock.now.duration(to: deadline)
            guard remainingBudget > .zero else { break }
            do {
                let data = try await executor.run(
                    arguments: ["--read-watch", candidate.route.parentID, "--watch-id", candidate.route.id, "--transport", transport.rawValue],
                    timeout: remainingBudget
                )
                let decoded = try MobileBatteryWire.decode(data, expectedParentID: candidate.route.parentID, observedAt: Date())
                var returnedWatch = false
                for snapshot in decoded.snapshots {
                    guard snapshot.parentID == candidate.route.parentID, snapshot.id == candidate.route.id else {
                        collected.failures.append(MobileBatteryReadFailure(category: "unsolicited-device", deviceID: snapshot.id))
                        continue
                    }
                    collected.snapshots.append(snapshot)
                    returnedWatch = true
                }
                collected.failures.append(contentsOf: decoded.failures)
                if returnedWatch { break }
            } catch is CancellationError {
                return collected
            } catch {
                if Task.isCancelled { return collected }
                collected.failures.append(MobileBatteryReadFailure(category: "read-failed", deviceID: candidate.route.id))
            }
        }
        return collected
    }

    private static func uniqueCandidates(_ candidates: [WatchCandidate]) -> [WatchCandidate] {
        var merged: [String: WatchCandidate] = [:]
        for candidate in candidates {
            let key = "\(candidate.route.parentID):\(candidate.route.id)"
            guard let existing = merged[key] else { merged[key] = candidate; continue }
            let available = Set(existing.transports + candidate.transports)
            let routes = ([MobileBatteryTransport.usb, .network] as [MobileBatteryTransport]).filter { available.contains($0) }
            let preferred = routes.first ?? existing.route.transport
            merged[key] = WatchCandidate(
                route: WatchRoute(id: candidate.route.id, parentID: candidate.route.parentID, transport: preferred),
                transports: routes
            )
        }
        return merged.values.sorted {
            if $0.route.parentID != $1.route.parentID { return $0.route.parentID < $1.route.parentID }
            return $0.route.id < $1.route.id
        }
    }

    private static func mergeCandidates(_ candidates: [AppleDeviceCandidate]) -> [AppleDeviceCandidate] {
        var merged: [AppleDeviceID: AppleDeviceCandidate] = [:]
        for candidate in candidates {
            guard let existing = merged[candidate.id] else { merged[candidate.id] = candidate; continue }
            let routes = ([MobileBatteryTransport.usb, .network] as [MobileBatteryTransport]).filter {
                existing.transports.contains($0) || candidate.transports.contains($0)
            }
            merged[candidate.id] = AppleDeviceCandidate(
                id: candidate.id,
                name: existing.name,
                model: existing.model ?? candidate.model,
                transports: routes,
                trustRequired: existing.trustRequired && candidate.trustRequired,
                evidence: existing.evidence
            )
        }
        return merged.values.sorted { $0.id.rowID < $1.id.rowID }
    }
}

private enum MobileBatteryHelperReadJob: Sendable {
    case phone(PhoneRoute)
    case watch(WatchCandidate)
}

private struct WatchCandidate: Sendable {
    let route: WatchRoute
    let transports: [MobileBatteryTransport]
}

private actor MobileBatteryReadAccumulator {
    private var result = MobileBatteryReadResult()

    func append(_ result: MobileBatteryReadResult) {
        self.result.snapshots.append(contentsOf: result.snapshots)
        self.result.failures.append(contentsOf: result.failures)
    }

    func snapshot() -> MobileBatteryReadResult { result }
}
