import Foundation
import Testing
import Darwin
@testable import StatusTrioCore

struct MobileBatteryHelperReaderTests {
    @Test func emptySelectedIDsPerformNoHelperCalls() async throws {
        let executor = ScriptedMobileBatteryExecutor { _ in Issue.record("empty authorization must not invoke helper"); return Data() }
        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: [])
        #expect(result.snapshots.isEmpty)
        #expect(await executor.recordedArguments.isEmpty)
    }

    @Test func selectedWatchReadsOnlyItsParentRouteAndNeverReadsParentBattery() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb","availableTransports":["usb","network"]},{"id":"q","transport":"usb"}]}"#.utf8)
            }
            if arguments == ["--read-watch", "p", "--watch-id", "w", "--transport", "usb"] {
                return Data(#"{"schemaVersion":1,"devices":[{"id":"w","parentID":"p","name":"Watch","model":"Watch7,4","batteryLevel":62,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
            }
            Issue.record("unexpected helper call: \(arguments)")
            return Data()
        }
        let selected: Set<AppleDeviceID> = [.trustedWatch(parentID: "p", id: "w")]
        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: selected)
        #expect(result.snapshots.map(\.identity) == ["watch:p:w"])
        let calls = await executor.recordedArguments
        #expect(calls.contains(["--list"]))
        #expect(calls.contains(["--read-watch", "p", "--watch-id", "w", "--transport", "usb"]))
        #expect(!calls.contains { $0.first == "--read-phone" || $0.first == "--discover-device" })
        #expect(!calls.contains { $0.contains("q") })
    }

    @Test func discoveryUsesMetadataCommandsAndNeverReadsBattery() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb"}]}"#.utf8)
            }
            if arguments == ["--discover-device", "p", "--transport", "usb"] {
                return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","name":"Phone","model":"iPhone18,1","transport":"usb","trustRequired":false},{"id":"w","parentID":"p","name":"Watch","model":"Watch7,4","transport":"usb","trustRequired":false}],"failures":[]}"#.utf8)
            }
            Issue.record("discovery must not make battery calls: \(arguments)")
            return Data()
        }
        let candidates = try await MobileBatteryHelperReader(executor: executor).discover()
        #expect(candidates.map(\.id).contains(.trustedDevice("p")))
        #expect(candidates.map(\.id).contains(.trustedWatch(parentID: "p", id: "w")))
        let calls = await executor.recordedArguments
        #expect(calls == [["--list"], ["--discover-device", "p", "--transport", "usb"]])
    }

    @Test func discoveryCapsTotalCandidatesAfterAppleFiltering() async throws {
        let phones = (0..<8).map { #"{"id":"p\#($0)","transport":"usb"}"# }.joined(separator: ",")
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] { return Data(#"{"schemaVersion":1,"phones":[\#(phones)]}"#.utf8) }
            guard arguments.first == "--discover-device" else { Issue.record("discovery made a battery call"); return Data() }
            let parent = arguments[1]
            let entries = (0..<3).map { #"{"id":"\#(parent)-w\#($0)","parentID":"\#(parent)","model":"Watch7,4","transport":"usb","trustRequired":false}"# }.joined(separator: ",")
            return Data(#"{"schemaVersion":1,"candidates":[{"id":"\#(parent)","model":"iPhone18,1","transport":"usb","trustRequired":false},\#(entries)],"failures":[]}"#.utf8)
        }
        let candidates = try await MobileBatteryHelperReader(executor: executor).discover()
        #expect(candidates.count == 8)
        #expect(candidates.allSatisfy { $0.isVerifiedTrustedAppleDevice })
    }

    /// A single iPhone's discovery group can exceed the candidate cap on its own.
    /// The group must stay whole: a Watch is only reachable through its phone's
    /// companion route, so trimming by hashed row ID would drop a Watch while
    /// keeping its phone, or keep a Watch whose phone was cut.
    @Test func discoveryKeepsAWatchWithItsPhoneWhenOneGroupExceedsTheCap() async throws {
        let watchEntries = (0..<8)
            .map { #"{"id":"w\#($0)","parentID":"p","model":"Watch7,4","transport":"usb","trustRequired":false}"# }
            .joined(separator: ",")
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb"}]}"#.utf8)
            }
            if arguments == ["--discover-device", "p", "--transport", "usb"] {
                return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","model":"iPhone18,1","transport":"usb","trustRequired":false},\#(watchEntries)],"failures":[]}"#.utf8)
            }
            Issue.record("unexpected helper call: \(arguments)")
            return Data()
        }
        let candidates = try await MobileBatteryHelperReader(executor: executor).discover()
        #expect(candidates.contains { $0.id == .trustedDevice("p") })
        #expect((0..<8).allSatisfy { index in
            candidates.contains { $0.id == .trustedWatch(parentID: "p", id: "w\(index)") }
        })
        #expect(candidates.allSatisfy { $0.isVerifiedTrustedAppleDevice })
    }

    /// A companion-discovered Watch inherits the iPhone route's transport. The
    /// helper never emits `.bluetooth` here, so the `.usb`/`.network` eligibility
    /// requirement does not reject it.
    @Test func discoveryInheritsThePhoneTransportForCompanionWatchCandidates() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"network","availableTransports":["network"]}]}"#.utf8)
            }
            if arguments == ["--discover-device", "p", "--transport", "network"] {
                return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","model":"iPhone18,1","transport":"network","trustRequired":false},{"id":"w","parentID":"p","model":"Watch7,4","transport":"network","trustRequired":false}],"failures":[]}"#.utf8)
            }
            Issue.record("unexpected helper call: \(arguments)")
            return Data()
        }
        let candidates = try await MobileBatteryHelperReader(executor: executor).discover()
        guard let watch = candidates.first(where: {
            $0.id == .trustedWatch(parentID: "p", id: "w")
        }) else {
            Issue.record("watch candidate missing: \(candidates.map(\.id))")
            return
        }
        #expect(watch.transports == [.network])
        #expect(watch.evidence == .verifiedAppleModel)
        #expect(watch.isVerifiedTrustedAppleDevice)
    }

    @Test func discoveryTriesNetworkCompanionWhenUSBReturnsOnlyPhoneMetadata() async throws {
        let executor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p","transport":"usb","availableTransports":["usb","network"]}]}"#.utf8)
            }
            if arguments.last == "usb" {
                return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","model":"iPhone18,1","transport":"usb","trustRequired":false}],"failures":[]}"#.utf8)
            }
            return Data(#"{"schemaVersion":1,"candidates":[{"id":"p","model":"iPhone18,1","transport":"network","trustRequired":false},{"id":"w","parentID":"p","transport":"network","trustRequired":false}],"failures":[]}"#.utf8)
        }
        let candidates = try await MobileBatteryHelperReader(executor: executor).discover()
        let watch = try #require(candidates.first { $0.id == .trustedWatch(parentID: "p", id: "w") })
        #expect(watch.transports == [.network])
        #expect(watch.evidence == .trustedWatchCompanion)
        #expect(watch.isVerifiedTrustedAppleDevice)
        #expect(await executor.recordedArguments == [
            ["--list"],
            ["--discover-device", "p", "--transport", "usb"],
            ["--discover-device", "p", "--transport", "network"],
        ])
    }

    /// The discovery summary is produced before the candidate cap, so a group
    /// the cap dropped, and the Watches inside it, stay visible in diagnostics.
    /// It carries counts only, never a device identifier.
    @Test func discoverySummaryCountsDroppedGroupsAndTheirWatches() {
        let summary = MobileBatteryDiscoverySummary.make(
            listedPhones: 9,
            probedPhones: 8,
            groups: [
                (candidateCount: 2, watchCount: 1),
                (candidateCount: 2, watchCount: 1),
                (candidateCount: 4, watchCount: 3),
            ],
            includedGroups: 2,
            retainedCandidates: 4
        )
        #expect(summary.listedPhones == 9)
        #expect(summary.probedPhones == 8)
        #expect(summary.discoveredCandidates == 8)
        #expect(summary.retainedCandidates == 4)
        #expect(summary.droppedGroups == 1)
        #expect(summary.droppedWatchCandidates == 3)
        #expect(summary.logDescription.split(separator: " ").count == 6)
    }

    /// A group larger than the whole budget is kept and never counted as
    /// dropped, so the summary cannot report impossible drops.
    @Test func discoverySummaryClampsIncludedGroupsToKnownGroups() {
        let summary = MobileBatteryDiscoverySummary.make(
            listedPhones: 1,
            probedPhones: 1,
            groups: [(candidateCount: 9, watchCount: 8)],
            includedGroups: 3,
            retainedCandidates: 9
        )
        #expect(summary.discoveredCandidates == 9)
        #expect(summary.droppedGroups == 0)
        #expect(summary.droppedWatchCandidates == 0)
    }

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
        let watches = ids.prefix(8).map { AppleDeviceID.trustedWatch(parentID: $0, id: "w-\($0)") }
        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: Set(ids.prefix(8).map(AppleDeviceID.trustedDevice) + watches))
        let recorded = await executor.recordedArguments
        #expect(recorded.filter { $0.first == "--read-phone" }.count == 8)
        #expect(recorded.filter { $0.first == "--read-watch" }.count == 8)
        #expect(recorded.filter { $0.first == "--read-phone" }.allSatisfy { $0.last == "usb" })
        #expect(await executor.maximumConcurrentRuns <= 2)
        #expect(result.snapshots.count == 16)
    }

    @Test func selectedWatchStartsBeforeUnrelatedPhoneReadsFinish() async throws {
        let executor = FairSchedulingMobileBatteryExecutor()
        let reader = MobileBatteryHelperReader(executor: executor)
        let readTask = Task {
            try await reader.read(selectedIDs: [
                .trustedDevice("p1"), .trustedDevice("p2"), .trustedDevice("p3"),
                .trustedWatch(parentID: "p1", id: "w1")
            ])
        }

        let watchStartedBeforePhoneRelease = await executor.waitForWatchOrBlockedPhonePair()
        await executor.releasePhones()
        let result = try await readTask.value

        #expect(watchStartedBeforePhoneRelease, "a requested Watch must start before two unrelated phone jobs can occupy the workers")
        #expect(result.snapshots.contains { $0.identity == "watch:p1:w1" })
        #expect(await executor.maximumConcurrentRuns <= 2)
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
        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: [.trustedDevice("slow"), .trustedDevice("fast")])
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

        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: [
            .trustedDevice("p1"), .trustedDevice("p2"), .trustedWatch(parentID: "p1", id: "w1")
        ])
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
        let result = try await MobileBatteryHelperReader(executor: executor, cycleTimeout: .milliseconds(300))
            .read(selectedIDs: [.trustedDevice("slow"), .trustedDevice("fast")])
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

        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: [
            .trustedDevice("p"), .trustedWatch(parentID: "p", id: "w")
        ])
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
        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: [.trustedDevice("p")])
        let recorded = await executor.recordedArguments
        #expect(recorded.filter { $0.first == "--read-phone" }.map(\.last) == ["usb", "network"])
        #expect(result.snapshots.first?.batteryLevel == 55)
    }

    @Test func hangingWatchDoesNotErasePhoneOrAnotherWatchesResult() async throws {
        let watchGate = TwoStageWatchOrderingGate()
        let scriptedExecutor = ScriptedMobileBatteryExecutor { arguments in
            if arguments == ["--list"] {
                return Data(#"{"schemaVersion":1,"phones":[{"id":"p1","transport":"usb"},{"id":"p2","transport":"usb"}]}"#.utf8)
            }
            if arguments.first == "--read-phone" {
                let phoneID = arguments[1]
                return Data(#"{"schemaVersion":1,"devices":[{"id":"\#(phoneID)","parentID":null,"name":null,"model":"iPhone17,1","batteryLevel":44,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[{"id":"w\#(phoneID)","parentID":"\#(phoneID)","transport":"usb"}]}"#.utf8)
            }
            if arguments.contains("wp1") {
                await watchGate.waitForPostAppendCompletion()
                throw MobileBatteryHelperError.timedOut
            }
            if arguments.contains("wp3") {
                return Data(#"{"schemaVersion":1,"devices":[],"failures":[],"watchCandidates":[]}"#.utf8)
            }
            let phoneID = arguments[1]
            let watchID = arguments[3]
            return Data(#"{"schemaVersion":1,"devices":[{"id":"\#(watchID)","parentID":"\#(phoneID)","name":null,"model":"Watch7,1","batteryLevel":66,"isCharging":null,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }
        let executor = TwoStageWatchOrderingExecutor(base: scriptedExecutor, gate: watchGate)
        let result = try await MobileBatteryHelperReader(executor: executor).read(selectedIDs: [
            .trustedDevice("p1"), .trustedDevice("p2"),
            .trustedWatch(parentID: "p1", id: "wp1"),
            .trustedWatch(parentID: "p2", id: "wp2"),
            .trustedWatch(parentID: "p2", id: "wp3")
        ])
        #expect(result.snapshots.map(\.id).sorted() == ["p1", "p2", "wp2"])
        #expect(await watchGate.observedEvents() == [
            .wp1Waiting,
            .wp2Completed,
            .postAppendSentinelReached,
            .wp1Resumed
        ])
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
        let script = try makeIgnoringTerminationScript()
        defer { try? FileManager.default.removeItem(at: script) }
        let (startStream, startContinuation) = AsyncStream.makeStream(of: Int32.self)
        let clock = ContinuousClock()
        let started = clock.now
        let processTask = Task {
            try await ProcessMobileBatteryHelperExecutor(
                helperURL: script,
                onProcessStarted: { startContinuation.yield($0) }
            )
                .run(arguments: [], timeout: .seconds(1))
        }
        defer { processTask.cancel() }
        var starts = startStream.makeAsyncIterator()
        let processID = try #require(await starts.next())
        do {
            _ = try await processTask.value
            Issue.record("timed out process must fail")
        } catch {
            #expect(error as? MobileBatteryHelperError == .timedOut)
            #expect(clock.now - started >= .milliseconds(1_200))
            // The runner may spend its 250 ms SIGKILL grace and 500 ms stream
            // drain grace after the 1 s deadline. Keep the result bounded while
            // allowing that documented post-deadline work on a loaded runner.
            #expect(clock.now - started < .seconds(5))
            errno = 0
            #expect(kill(processID, 0) == -1 && errno == ESRCH)
        }
    }

    @Test func cancellationTerminatesTheProcessAndCompletesOnce() async throws {
        let script = try makeIgnoringTerminationScript()
        defer { try? FileManager.default.removeItem(at: script) }
        let (startStream, startContinuation) = AsyncStream.makeStream(of: Int32.self)
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await ProcessMobileBatteryHelperExecutor(
                helperURL: script,
                onProcessStarted: { startContinuation.yield($0) }
            )
                .run(arguments: [], timeout: .seconds(10))
        }
        defer { task.cancel() }
        var starts = startStream.makeAsyncIterator()
        let processID = try #require(await starts.next())
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("cancelled process must fail")
        } catch {
            #expect(error as? MobileBatteryHelperError == .cancelled)
            // Once launch is reported, cancellation is immediate; there is no
            // cancellation delay in BoundedProcessInvocation. Only the timeout
            // path has a 1 s deadline. Bound the operation without inventing a
            // minimum that contradicts the implementation.
            #expect(clock.now - started < .seconds(5))
            errno = 0
            #expect(kill(processID, 0) == -1 && errno == ESRCH)
        }
    }

    @Test func processExecutorFinishesWhenADescendantHoldsThePipes() async throws {
        // The helper exits immediately but leaves a child holding the inherited
        // stdout/stderr, so the stream-ended flags never arrive. The invocation
        // must still finish at its deadline instead of waiting for that child.
        let script = try makeScript("sleep 5 & exit 0")
        defer { try? FileManager.default.removeItem(at: script) }
        let clock = ContinuousClock()
        let started = clock.now

        do {
            _ = try await ProcessMobileBatteryHelperExecutor(helperURL: script)
                .run(arguments: [], timeout: .milliseconds(500))
            Issue.record("an invocation whose pipes are held must time out")
        } catch {
            #expect(error as? MobileBatteryHelperError == .timedOut)
            #expect(clock.now - started < .seconds(3))
        }
    }

    private func makeIgnoringTerminationScript() throws -> URL {
        try makeScript(
            """
            trap '' TERM
            while :; do
                /bin/sleep 0.01
            done
            """
        )
    }

    private func makeScript(_ body: String, interpreter: String = "/bin/sh") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mobile-battery-\(UUID().uuidString).sh")
        try Data("#!\(interpreter)\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

private actor TwoStageWatchOrderingExecutor: MobileBatteryHelperExecuting {
    private let base: ScriptedMobileBatteryExecutor
    private let gate: TwoStageWatchOrderingGate

    init(base: ScriptedMobileBatteryExecutor, gate: TwoStageWatchOrderingGate) {
        self.base = base
        self.gate = gate
    }

    func run(arguments: [String], timeout: Duration) async throws -> Data {
        let isWP2 = arguments.contains("wp2")
        if isWP2 {
            await gate.waitUntilWP1IsWaiting()
        }
        let data = try await base.run(arguments: arguments, timeout: timeout)
        if isWP2 {
            await gate.markWP2Completed()
        } else if arguments.contains("wp3") {
            await gate.markPostAppendSentinelReached()
        }
        return data
    }
}

private actor TwoStageWatchOrderingGate {
    enum Event: Equatable, Sendable {
        case wp1Waiting
        case wp2Completed
        case postAppendSentinelReached
        case wp1Resumed
    }

    private enum WaiterKey: Hashable, Sendable {
        case wp2MayComplete
        case wp1MayResume
    }

    private var wp1Waiting = false
    private var wp2Completed = false
    private var postAppendSentinelReached = false
    private var wp1Resumed = false
    private var events: [Event] = []
    private var waiters: [WaiterKey: [UUID: CheckedContinuation<Void, Never>]] = [:]
    private var cancelledWaiterIDs: [WaiterKey: Set<UUID>] = [:]

    func waitUntilWP1IsWaiting() async {
        guard !wp1Waiting else { return }
        await park(.wp2MayComplete)
    }

    func waitForPostAppendCompletion() async {
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enqueueWP1Waiter(continuation, id: waiterID)
            }
        } onCancel: {
            Task { await self.cancelWaiter(for: .wp1MayResume, id: waiterID) }
        }
        if wp2Completed && postAppendSentinelReached {
            markWP1Resumed()
        }
    }

    func markWP2Completed() {
        wp2Completed = true
        events.append(.wp2Completed)
        resumeWP1IfPostAppendCompleted()
    }

    func markPostAppendSentinelReached() {
        postAppendSentinelReached = true
        events.append(.postAppendSentinelReached)
        resumeWP1IfPostAppendCompleted()
    }

    func observedEvents() -> [Event] {
        events
    }

    private func park(_ key: WaiterKey) async {
        let waiterID = UUID()
        await withTaskCancellationHandler {
            if conditionSatisfied(for: key) { return }
            await withCheckedContinuation { continuation in
                enqueue(continuation, for: key, id: waiterID)
            }
        } onCancel: {
            Task { await self.cancelWaiter(for: key, id: waiterID) }
        }
    }

    private func enqueueWP1Waiter(_ continuation: CheckedContinuation<Void, Never>, id: UUID) {
        if cancelledWaiterIDs[.wp1MayResume]?.remove(id) != nil {
            continuation.resume()
            return
        }
        if wp2Completed && postAppendSentinelReached {
            wp1Waiting = true
            events.append(.wp1Waiting)
            continuation.resume()
            return
        }
        waiters[.wp1MayResume, default: [:]][id] = continuation
        guard !wp1Waiting else { return }
        wp1Waiting = true
        events.append(.wp1Waiting)
        resumeWaiters(for: .wp2MayComplete)
    }

    private func enqueue(
        _ continuation: CheckedContinuation<Void, Never>,
        for key: WaiterKey,
        id: UUID
    ) {
        if conditionSatisfied(for: key) || cancelledWaiterIDs[key]?.remove(id) != nil {
            continuation.resume()
        } else {
            waiters[key, default: [:]][id] = continuation
        }
    }

    private func cancelWaiter(for key: WaiterKey, id: UUID) {
        if let continuation = waiters[key]?.removeValue(forKey: id) {
            continuation.resume()
        } else if !conditionSatisfied(for: key) {
            cancelledWaiterIDs[key, default: []].insert(id)
        }
    }

    private func conditionSatisfied(for key: WaiterKey) -> Bool {
        switch key {
        case .wp2MayComplete:
            wp1Waiting
        case .wp1MayResume:
            wp2Completed && postAppendSentinelReached
        }
    }

    private func resumeWP1IfPostAppendCompleted() {
        guard wp2Completed && postAppendSentinelReached else { return }
        resumeWaiters(for: .wp1MayResume)
    }

    private func resumeWaiters(for key: WaiterKey) {
        let continuations = waiters.removeValue(forKey: key) ?? [:]
        cancelledWaiterIDs.removeValue(forKey: key)
        for continuation in continuations.values {
            continuation.resume()
        }
    }

    private func markWP1Resumed() {
        guard !wp1Resumed else { return }
        wp1Resumed = true
        events.append(.wp1Resumed)
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

private actor FairSchedulingMobileBatteryExecutor: MobileBatteryHelperExecuting {
    private var phoneContinuations: [String: CheckedContinuation<Data, any Error>] = [:]
    private var schedulingDecisionWaiters: [CheckedContinuation<Bool, Never>] = []
    private var watchStarted = false
    private var phonesReleased = false
    private var activeRuns = 0
    private(set) var maximumConcurrentRuns = 0

    func run(arguments: [String], timeout: Duration) async throws -> Data {
        activeRuns += 1
        maximumConcurrentRuns = max(maximumConcurrentRuns, activeRuns)
        defer { activeRuns -= 1 }

        if arguments == ["--list"] {
            return Data(#"{"schemaVersion":1,"phones":[{"id":"p1","transport":"usb"},{"id":"p2","transport":"usb"},{"id":"p3","transport":"usb"}]}"#.utf8)
        }

        if arguments.first == "--read-phone" {
            let phoneID = arguments[1]
            if phonesReleased { return Self.phoneData(id: phoneID) }
            return try await withCheckedThrowingContinuation { continuation in
                phoneContinuations[phoneID] = continuation
                resumeSchedulingDecisionIfReady()
            }
        }

        if arguments.first == "--read-watch" {
            watchStarted = true
            resumeSchedulingDecisionIfReady()
            return Data(#"{"schemaVersion":1,"devices":[{"id":"w1","parentID":"p1","name":"Watch","model":"Watch7,4","batteryLevel":62,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
        }

        throw MobileBatteryHelperError.processFailed
    }

    func waitForWatchOrBlockedPhonePair() async -> Bool {
        if watchStarted { return true }
        if phoneContinuations.count >= 2 { return false }
        return await withCheckedContinuation { schedulingDecisionWaiters.append($0) }
    }

    func releasePhones() {
        phonesReleased = true
        let pending = phoneContinuations
        phoneContinuations.removeAll()
        for (phoneID, continuation) in pending {
            continuation.resume(returning: Self.phoneData(id: phoneID))
        }
    }

    private func resumeSchedulingDecisionIfReady() {
        guard watchStarted || phoneContinuations.count >= 2 else { return }
        let result = watchStarted
        let waiters = schedulingDecisionWaiters
        schedulingDecisionWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
    }

    private static func phoneData(id: String) -> Data {
        Data(#"{"schemaVersion":1,"devices":[{"id":"\#(id)","parentID":null,"name":"Phone","model":"iPhone17,1","batteryLevel":55,"isCharging":false,"transport":"usb"}],"failures":[],"watchCandidates":[]}"#.utf8)
    }
}
