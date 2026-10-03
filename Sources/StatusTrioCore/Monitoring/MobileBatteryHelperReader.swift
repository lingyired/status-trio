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
        let invocation = ProcessInvocation(executableURL: helperURL, arguments: arguments)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                invocation.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            invocation.cancel()
        }
    }
}

private final class ProcessInvocation: @unchecked Sendable {
    private static let streamLimit = 1_048_576

    private let queue = DispatchQueue(label: "StatusTrio.MobileBattery.Process")
    private let executableURL: URL
    private let arguments: [String]
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdout = Data()
    private var stderrCount = 0
    private var stdoutEnded = false
    private var stderrEnded = false
    private var processEnded = false
    private var hasStarted = false
    private var cancelled = false
    private var failure: MobileBatteryHelperError?
    private var continuation: CheckedContinuation<Data, any Error>?

    init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    func start(timeout: Duration, continuation: CheckedContinuation<Data, any Error>) {
        queue.async {
            self.continuation = continuation
            guard !self.cancelled else {
                self.failure = .cancelled
                self.stdoutEnded = true
                self.stderrEnded = true
                self.processEnded = true
                self.completeIfReady()
                return
            }

            let child = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            child.executableURL = self.executableURL
            child.arguments = self.arguments
            child.standardOutput = stdoutPipe
            child.standardError = stderrPipe
            self.process = child
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak invocation = self] handle in
                let data = handle.availableData
                guard let invocation else { return }
                invocation.queue.async { [invocation] in invocation.received(data, stream: .stdout) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak invocation = self] handle in
                let data = handle.availableData
                guard let invocation else { return }
                invocation.queue.async { [invocation] in invocation.received(data, stream: .stderr) }
            }
            child.terminationHandler = { [weak invocation = self] terminated in
                guard let invocation else { return }
                invocation.queue.async { [invocation] in
                    invocation.processEnded = true
                    if terminated.terminationReason != .exit || terminated.terminationStatus != 0 {
                        invocation.failure = invocation.failure ?? .processFailed
                    }
                    invocation.completeIfReady()
                }
            }

            do {
                try child.run()
                self.hasStarted = true
                let duration = timeout.components
                let timeoutSeconds = Double(duration.seconds) + Double(duration.attoseconds) / 1_000_000_000_000_000_000
                self.queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    guard !self.processEnded else { return }
                    self.failure = self.failure ?? .timedOut
                    self.terminateThenKill()
                }
            } catch {
                self.failure = .processFailed
                self.processEnded = true
                self.stdoutEnded = true
                self.stderrEnded = true
                self.completeIfReady()
            }
        }
    }

    func cancel() {
        queue.async {
            guard !self.processEnded else { return }
            self.cancelled = true
            self.failure = .cancelled
            if self.hasStarted { self.terminateThenKill() }
            else {
                self.processEnded = true
                self.stdoutEnded = true
                self.stderrEnded = true
                self.completeIfReady()
            }
        }
    }

    private enum Stream { case stdout, stderr }

    private func received(_ data: Data, stream: Stream) {
        if data.isEmpty {
            switch stream {
            case .stdout:
                stdoutEnded = true
                stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            case .stderr:
                stderrEnded = true
                stderrPipe?.fileHandleForReading.readabilityHandler = nil
            }
            completeIfReady()
            return
        }
        switch stream {
        case .stdout:
            guard stdout.count + data.count <= Self.streamLimit else {
                failure = failure ?? .outputTooLarge
                terminateThenKill()
                return
            }
            stdout.append(data)
        case .stderr:
            guard stderrCount + data.count <= Self.streamLimit else {
                failure = failure ?? .outputTooLarge
                terminateThenKill()
                return
            }
            stderrCount += data.count
        }
    }

    private func terminateThenKill() {
        guard let child = process, child.isRunning else { return }
        child.terminate()
        let pid = child.processIdentifier
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) {
            guard child.isRunning else { return }
            _ = kill(pid, SIGKILL)
        }
    }

    private func completeIfReady() {
        guard processEnded, stdoutEnded, stderrEnded, let continuation else { return }
        self.continuation = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        stdoutPipe = nil
        stderrPipe = nil
        process?.terminationHandler = nil
        process = nil
        if let failure { continuation.resume(throwing: failure) }
        else { continuation.resume(returning: stdout) }
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

    func read() async throws -> MobileBatteryReadResult {
        let accumulator = MobileBatteryReadAccumulator()
        return try await withThrowingTaskGroup(of: MobileBatteryReadResult.self) { group in
            group.addTask { try await readCycle(accumulator) }
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

    private func readCycle(_ accumulator: MobileBatteryReadAccumulator) async throws -> MobileBatteryReadResult {
        try Task.checkCancellation()
        let listingData = try await executor.run(arguments: ["--list"], timeout: .seconds(3))
        let phones = try MobileBatteryWire.decodeListing(listingData).prefix(8)
        let candidates = await readPhones(Array(phones), accumulator: accumulator)
        guard !Task.isCancelled else { return await accumulator.snapshot() }
        let limitedCandidates = Self.uniqueCandidates(candidates).prefix(8)
        await readWatches(Array(limitedCandidates), accumulator: accumulator)
        return await accumulator.snapshot()
    }

    private func readPhones(_ phones: [PhoneRoute], accumulator: MobileBatteryReadAccumulator) async -> [WatchCandidate] {
        await withTaskGroup(of: PhoneResult.self, returning: [WatchCandidate].self) { group in
            var nextIndex = 0
            for _ in 0..<min(2, phones.count) {
                let phone = phones[nextIndex]
                nextIndex += 1
                group.addTask { await readPhone(phone) }
            }
            var candidates: [WatchCandidate] = []
            while let result = await group.next() {
                await accumulator.append(result.result)
                candidates.append(contentsOf: result.watchCandidates)
                if !Task.isCancelled, nextIndex < phones.count {
                    let phone = phones[nextIndex]
                    nextIndex += 1
                    group.addTask { await readPhone(phone) }
                }
            }
            return candidates
        }
    }

    private func readPhone(_ phone: PhoneRoute) async -> PhoneResult {
        var collected = MobileBatteryReadResult()
        var candidates: [WatchCandidate] = []
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
                let discovered = try MobileBatteryWire.decodeWatchCandidates(data, expectedParentID: phone.id)
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
                candidates.append(contentsOf: discovered.map { WatchCandidate(route: $0, transports: phone.transports) })
                if returnedPhone { break }
            } catch is CancellationError {
                return PhoneResult(result: collected, watchCandidates: candidates)
            } catch {
                if Task.isCancelled { return PhoneResult(result: collected, watchCandidates: candidates) }
                collected.failures.append(MobileBatteryReadFailure(category: "read-failed", deviceID: phone.id))
            }
        }
        return PhoneResult(result: collected, watchCandidates: candidates)
    }

    private func readWatches(_ candidates: [WatchCandidate], accumulator: MobileBatteryReadAccumulator) async {
        await withTaskGroup(of: MobileBatteryReadResult.self, returning: Void.self) { group in
            var nextIndex = 0
            for _ in 0..<min(2, candidates.count) {
                let candidate = candidates[nextIndex]
                nextIndex += 1
                group.addTask { await readWatch(candidate) }
            }
            while let result = await group.next() {
                await accumulator.append(result)
                if !Task.isCancelled, nextIndex < candidates.count {
                    let candidate = candidates[nextIndex]
                    nextIndex += 1
                    group.addTask { await readWatch(candidate) }
                }
            }
        }
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
}

private struct PhoneResult: Sendable {
    let result: MobileBatteryReadResult
    let watchCandidates: [WatchCandidate]
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
