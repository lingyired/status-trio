import Foundation
import Testing
import Darwin
@testable import StatusTrioCore

struct MobileBatteryHelperReaderTests {
    @Test func defaultExecutorResolvesThePackagedHelperName() async throws {
        if let packagedBundlePath = ProcessInfo.processInfo.environment["STATUS_TRIO_MOBILE_BATTERY_BUNDLE_URL"] {
            let bundle = URL(fileURLWithPath: packagedBundlePath, isDirectory: true)
            let output = try await ProcessMobileBatteryHelperExecutor(bundleURL: bundle)
                .run(arguments: ["--list"], timeout: .seconds(3))
            #expect(try MobileBatteryWire.decodeListing(output).count == 0)
            return
        }

        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("MobileBattery-\(UUID().uuidString).app", isDirectory: true)
        let helper = bundle.appendingPathComponent("Contents/Helpers/StatusTrioMobileBatteryHelper")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf packaged-helper".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        defer { try? FileManager.default.removeItem(at: bundle) }

        let output = try await ProcessMobileBatteryHelperExecutor(bundleURL: bundle)
            .run(arguments: [], timeout: .seconds(2))
        #expect(String(decoding: output, as: UTF8.self) == "packaged-helper")
    }

    @Test func boundsPhoneReadsAndDeduplicatesRoutes() async throws {
        let ids = (0..<9).map { "p\($0)" }
        let phones = ids.map { #"{"id":"\#($0)","transport":"network","availableTransports":["network","usb"]}"# }.joined(separator: ",")
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] { return Data(#"{"schemaVersion":1,"phones":[\#(phones)]}"#.utf8) }
            if arguments.first == "--read-phone" {
                let phoneID = arguments[1]
                return Data(#"{"schemaVersion":1,"devices":[{"id":"\#(phoneID)","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":45,"isCharging":false,"transport":"\#(arguments.last ?? "usb")"}],"failures":[],"watchCandidates":[{"id":"w-\#(phoneID)","parentID":"\#(phoneID)","transport":"usb"}]}"#.utf8)
            }
            let phoneID = arguments[1]
            let watchID = arguments[3]
            return Data(#"{"schemaVersion":1,"devices":[{"id":"\#(watchID)","parentID":"\#(phoneID)","name":null,"model":"Watch7,1","batteryLevel":60,"isCharging":null,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }
        let result = try await MobileBatteryHelperReader(executor: executor).read()
        let recorded = await executor.recordedArguments
        #expect(recorded.filter { $0.first == "--read-phone" }.count == 8)
        #expect(recorded.filter { $0.first == "--read-watch" }.count == 8)
        #expect(recorded.filter { $0.first == "--read-phone" }.allSatisfy { $0.last == "usb" })
        #expect(await executor.maximumConcurrentRuns <= 2)
        #expect(result.snapshots.count == 16)
    }

    @Test func onePhoneTimeoutDoesNotDiscardAnotherPhonesSnapshot() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"slow","transport":"usb"},{"id":"fast","transport":"usb"}]}"#.utf8)
            }
            if arguments.first == "--read-phone", arguments[1] == "slow" {
                try await Task.sleep(for: .milliseconds(100))
                throw MobileBatteryHelperError.timedOut
            }
            return Data(#"{"schemaVersion":1,"devices":[{"id":"fast","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":42,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }
        let result = try await MobileBatteryHelperReader(executor: executor).read()
        #expect(result.snapshots.map(\.id) == ["fast"])
    }

    @Test func rejectsUnsolicitedSnapshotsWhileKeepingRequestedResults() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p1","transport":"usb"},{"id":"p2","transport":"usb"}]}"#.utf8)
            }
            if arguments.first == "--read-phone", arguments[1] == "p1" {
                return Data(#"{"schemaVersion":1,"devices":[{"id":"p1","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":41,"isCharging":false,"transport":"usb"},{"id":"unsolicited-phone","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":90,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[{"id":"w1","parentID":"p1","transport":"usb"}]}"#.utf8)
            }
            if arguments.first == "--read-phone" {
                return Data(#"{"schemaVersion":1,"devices":[{"id":"wrong-only","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":80,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
            }
            return Data(#"{"schemaVersion":1,"devices":[{"id":"w1","parentID":"p1","name":null,"model":"Watch7,1","batteryLevel":61,"isCharging":null,"transport":"usb"},{"id":"unsolicited-watch","parentID":"p1","name":null,"model":"Watch7,1","batteryLevel":90,"isCharging":null,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }

        let result = try await MobileBatteryHelperReader(executor: executor).read()
        #expect(Set(result.snapshots.map(\.id)) == ["p1", "w1"])
        #expect(result.failures.filter { $0.category == "unsolicited-device" }.count == 3)
    }

    @Test func completedPhoneSurvivesOverallCycleDeadline() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"slow","transport":"usb"},{"id":"fast","transport":"usb"}]}"#.utf8)
            }
            if arguments.first == "--read-phone", arguments[1] == "slow" {
                try await Task.sleep(for: .seconds(10))
                throw MobileBatteryHelperError.timedOut
            }
            return Data(#"{"schemaVersion":1,"devices":[{"id":"fast","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":42,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }
        let result = try await MobileBatteryHelperReader(executor: executor, cycleTimeout: .milliseconds(300)).read()
        #expect(result.snapshots.map(\.id) == ["fast"])
        #expect(result.failures.contains { $0.category == "cycle-timeout" })
    }

    @Test func watchFallbackUsesTheRemainingSharedBudget() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb","availableTransports":["usb","network"]}]}"#.utf8)
            }
            if arguments.first == "--read-phone" {
                return Data(#"{"schemaVersion":1,"devices":[{"id":"p","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":41,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[{"id":"w","parentID":"p","transport":"usb"}]}"#.utf8)
            }
            if arguments.last == "usb" {
                try await Task.sleep(for: .milliseconds(100))
                throw MobileBatteryHelperError.processFailed
            }
            return Data(#"{"schemaVersion":1,"devices":[{"id":"w","parentID":"p","name":null,"model":"Watch7,1","batteryLevel":61,"isCharging":null,"transport":"network"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }

        let result = try await MobileBatteryHelperReader(executor: executor).read()
        let timeouts = await executor.recordedTimeouts
        let arguments = await executor.recordedArguments
        let watchTimeouts = zip(arguments, timeouts)
            .filter { $0.0.first == "--read-watch" }
            .map { $0.1 }
        #expect(result.snapshots.contains { $0.id == "w" })
        #expect(watchTimeouts.count == 2)
        #expect(watchTimeouts[1] < .seconds(5))
    }

    @Test func retriesOnlyDiscoveredNetworkRouteAfterUSBFailure() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb","availableTransports":["usb","network"]}]}"#.utf8)
            }
            if arguments == ["--read-phone", "p", "--transport", "usb"] { throw MobileBatteryHelperError.processFailed }
            if arguments == ["--read-phone", "p", "--transport", "network"] {
                return Data(#"{"schemaVersion":1,"devices":[{"id":"p","parentID":null,"name":"Phone","model":"iPhone17,1","batteryLevel":55,"isCharging":false,"transport":"network"}],"failures":[],"watchCandidates":[]}"#.utf8)
            }
            throw MobileBatteryHelperError.processFailed
        }
        let result = try await MobileBatteryHelperReader(executor: executor).read()
        let recorded = await executor.recordedArguments
        #expect(recorded.filter { $0.first == "--read-phone" }.map(\.last) == ["usb", "network"])
        #expect(result.snapshots.first?.batteryLevel == 55)
    }

    @Test func hangingWatchDoesNotErasePhoneOrAnotherWatchesResult() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p1","transport":"usb"},{"id":"p2","transport":"usb"}]}"#.utf8)
            }
            if arguments.first == "--read-phone" {
                let phoneID = arguments[1]
                return Data(#"{"schemaVersion":1,"devices":[{"id":"\#(phoneID)","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":44,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[{"id":"w\#(phoneID)","parentID":"\#(phoneID)","transport":"usb"}]}"#.utf8)
            }
            if arguments.contains("wp1") {
                try await Task.sleep(for: .seconds(5))
                throw MobileBatteryHelperError.timedOut
            }
            let phoneID = arguments[1]
            let watchID = arguments[3]
            return Data(#"{"schemaVersion":1,"devices":[{"id":"\#(watchID)","parentID":"\#(phoneID)","name":null,"model":"Watch7,1","batteryLevel":66,"isCharging":null,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }
        let result = try await MobileBatteryHelperReader(executor: executor).read()
        #expect(result.snapshots.contains { $0.id == "p1" })
        #expect(result.snapshots.contains { $0.id == "p2" })
        #expect(result.snapshots.contains { $0.id == "wp2" })
    }

    @Test func processExecutorReturnsStdoutAndRejectsLargeStreamsAndExitStatus() async throws {
        let small = try makeScript("printf 'hello'")
        defer { try? FileManager.default.removeItem(at: small) }
        let output = try await ProcessMobileBatteryHelperExecutor(helperURL: small).run(arguments: [], timeout: .seconds(2))
        #expect(String(decoding: output, as: UTF8.self) == "hello")

        let largeOutput = try makeScript("yes x | head -c 1048577")
        defer { try? FileManager.default.removeItem(at: largeOutput) }
        await #expect(throws: (any Error).self) {
            try await ProcessMobileBatteryHelperExecutor(helperURL: largeOutput).run(arguments: [], timeout: .seconds(3))
        }

        let largeError = try makeScript("yes x | head -c 1048577 >&2")
        defer { try? FileManager.default.removeItem(at: largeError) }
        await #expect(throws: (any Error).self) {
            try await ProcessMobileBatteryHelperExecutor(helperURL: largeError).run(arguments: [], timeout: .seconds(3))
        }

        let nonzero = try makeScript("echo private-stderr >&2; exit 17")
        defer { try? FileManager.default.removeItem(at: nonzero) }
        do {
            _ = try await ProcessMobileBatteryHelperExecutor(helperURL: nonzero).run(arguments: [], timeout: .seconds(2))
            Issue.record("nonzero exit must fail")
        } catch {
            #expect(!String(describing: error).contains("private-stderr"))
        }
    }

    @Test func processExecutorKillsAChildThatIgnoresTermination() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("mobile-battery-pid-\(UUID().uuidString)")
        let script = try makeIgnoringTerminationScript(pidFile: pidFile)
        defer { try? FileManager.default.removeItem(at: script) }
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let clock = ContinuousClock()
        let started = clock.now
        let processTask = Task {
            try await ProcessMobileBatteryHelperExecutor(helperURL: script).run(arguments: [], timeout: .seconds(1))
        }
        try await waitForPIDFile(pidFile)
        do {
            _ = try await processTask.value
            Issue.record("timed out process must fail")
        } catch {
            #expect(error as? MobileBatteryHelperError == .timedOut)
            #expect(clock.now - started >= .milliseconds(1_200))
            #expect(clock.now - started < .seconds(2))
            let processID = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            errno = 0
            #expect(kill(processID, 0) == -1 && errno == ESRCH)
        }
    }

    @Test func cancellationTerminatesTheProcessAndCompletesOnce() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("mobile-battery-pid-\(UUID().uuidString)")
        let script = try makeIgnoringTerminationScript(pidFile: pidFile)
        defer { try? FileManager.default.removeItem(at: script) }
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await ProcessMobileBatteryHelperExecutor(helperURL: script).run(arguments: [], timeout: .seconds(10))
        }
        try await waitForPIDFile(pidFile)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("cancelled process must fail")
        } catch {
            #expect(error as? MobileBatteryHelperError == .cancelled)
            #expect(clock.now - started >= .milliseconds(250))
            #expect(clock.now - started < .seconds(2))
            let processID = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            errno = 0
            #expect(kill(processID, 0) == -1 && errno == ESRCH)
        }
    }

    private func makeIgnoringTerminationScript(pidFile: URL) throws -> URL {
        let script = try makeScript(
            "import os, signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nwith open(\(String(reflecting: pidFile.path)), 'w') as f: f.write(str(os.getpid()))\nprint('ready', flush=True)\nwhile True: time.sleep(0.01)",
            interpreter: "/usr/bin/python3"
        )
        return script
    }

    private func waitForPIDFile(_ url: URL) async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("child process did not reach its ready signal")
    }

    private func makeScript(_ body: String, interpreter: String = "/bin/sh") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mobile-battery-\(UUID().uuidString).sh")
        try Data("#!\(interpreter)\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

private actor ScriptedMobileBatteryExecutor: MobileBatteryHelperExecuting {
    typealias Handler = @Sendable ([String]) async throws -> Data
    private let handler: Handler
    private(set) var recordedArguments: [[String]] = []
    private(set) var recordedTimeouts: [Duration] = []
    private var activeRuns = 0
    private(set) var maximumConcurrentRuns = 0

    init(handler: @escaping Handler) { self.handler = handler }

    func run(arguments: [String], timeout: Duration) async throws -> Data {
        recordedArguments.append(arguments)
        recordedTimeouts.append(timeout)
        activeRuns += 1
        maximumConcurrentRuns = max(maximumConcurrentRuns, activeRuns)
        defer { activeRuns -= 1 }
        return try await handler(arguments)
    }
}
