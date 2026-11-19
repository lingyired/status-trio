import Foundation
import Testing
@testable import StatusTrioCore

private final class RecordingTopAppExecutor: TopAppCommandExecuting, @unchecked Sendable {
    let output: Data
    private(set) var invocations: [(URL, [String])] = []

    init(output: Data) { self.output = output }

    func run(executableURL: URL, arguments: [String]) async -> Result<Data, TopAppReadError> {
        invocations.append((executableURL, arguments))
        return .success(output)
    }
}

private struct StubMetadataReader: ProcessMetadataReading {
    let names: [Int32: String]

    func metadata(for pid: Int32, fallbackName: String) -> ProcessMetadata? {
        ProcessMetadata(identity: ProcessIdentity(pid: pid, startedAt: 42),
                        name: names[pid] ?? fallbackName,
                        executablePath: nil,
                        responsiblePID: nil)
    }
}

struct TopAppCommandReaderTests {
    @Test func testCPUParsesAllRowsAndKeeps240Point5Percent() {
        let output = """
          PID  %CPU COMM
            1 240.5 Foo
            2  12.0 Bar Baz
            3   9.5 Qux
            4   8.0 Quux
            5   7.0 Corge
            6   6.0 Grault
        """
        let result = TopAppPSParser.parse(Data(output.utf8))
        guard case .success(let rows) = result else {
            Issue.record("expected parsed rows")
            return
        }
        #expect(rows.count == 6)
        #expect(rows.first?.cpuPercent == 240.5)
        #expect(rows.first?.name == "Foo")
        #expect(rows[1].name == "Bar Baz")
    }

    @Test func testTopMemoryUnitsNamesAndMarkers() {
        #expect(TopAppTopParser.memoryBytes("1.5G") == 1_610_612_736)
        #expect(TopAppTopParser.memoryBytes("512M+") == 536_870_912)
        #expect(TopAppTopParser.memoryBytes("1632K") == 1_671_168)
        #expect(TopAppTopParser.memoryBytes("1.25T") == 1_374_389_534_720)
        #expect(TopAppTopParser.memoryBytes("900") == 900)
        #expect(TopAppTopParser.memoryBytes("abc") == nil)

        let output = """
        Processes: 1 total
        PID    COMMAND          MEM
          123   Google Chrome Helper   1.5G
          456   com.apple.Driver      976M-
        """
        let result = TopAppTopParser.parse(Data(output.utf8))
        guard case .success(let rows) = result else {
            Issue.record("expected parsed rows")
            return
        }
        #expect(rows.count == 2)
        #expect(rows[0].name == "Google Chrome Helper")
        #expect(rows[0].memoryBytes == 1_610_612_736)
        #expect(rows[1].name == "com.apple.Driver")
    }

    @Test func testPSMemoryConvertsRSSAndSkipsOverflowingRows() {
        let output = """
        PID RSS COMM
          1 1024 Example App
          2 18446744073709551615 Too Big
          3 notanumber Broken
          4 2048 Other
        """
        let result = TopAppPSMemoryParser.parse(Data(output.utf8))
        guard case .success(let rows) = result else {
            Issue.record("expected parsed rows")
            return
        }
        #expect(rows.count == 2)
        #expect(rows[0] == PSMemoryRow(pid: 1, memoryBytes: 1_048_576, name: "Example App"))
        #expect(rows[1] == PSMemoryRow(pid: 4, memoryBytes: 2_097_152, name: "Other"))
    }

    @Test func testInvocationReceivesFixedLocaleAndExactArguments() async {
        let output = "  PID  %CPU COMM\n    1   1.0 Foo\n"
        let executor = RecordingTopAppExecutor(output: Data(output.utf8))
        let reader = TopAppCPUReader(executor: executor, metadataReader: StubMetadataReader(names: [:]))
        _ = await reader.read()

        #expect(executor.invocations.count == 1)
        #expect(executor.invocations.first?.0.path == "/bin/ps")
        #expect(executor.invocations.first?.1 == ["-Aceo", "pid,pcpu,comm", "-r"])

        let memoryOutput = "PID   RSS COMM\n    1  1024 Foo\n"
        let memoryExecutor = RecordingTopAppExecutor(output: Data(memoryOutput.utf8))
        let memoryReader = TopAppMemoryReader(executor: memoryExecutor, metadataReader: StubMetadataReader(names: [:]))
        _ = await memoryReader.read()
        
        #expect(memoryExecutor.invocations.first?.0.path == "/bin/ps")
        #expect(memoryExecutor.invocations.first?.1 == ["-Aceo", "pid,rss,comm"])
    }

    @Test func testMalformedOutputIsNotSuccessfulEmptyList() async {
        let executor = RecordingTopAppExecutor(output: Data("not a process table".utf8))
        let reader = TopAppCPUReader(executor: executor, metadataReader: StubMetadataReader(names: [:]))
        let result = await reader.read()
        if case .failure(.malformedOutput) = result {
            #expect(Bool(true))
        } else {
            Issue.record("expected malformedOutput, got \(result)")
        }

        let topExecutor = RecordingTopAppExecutor(output: Data("nonsense".utf8))
        let topReader = TopAppMemoryReader(executor: topExecutor, metadataReader: StubMetadataReader(names: [:]))
        let topResult = await topReader.read()
        if case .failure(.malformedOutput) = topResult {
            #expect(Bool(true))
        } else {
            Issue.record("expected malformedOutput, got \(topResult)")
        }
    }

    @Test func testBoundedInvocationAppliesEnvironment() {
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf %s \"$LC_ALL\""],
            timeout: .seconds(2),
            environment: ["LC_ALL": "C"]
        )
        #expect(outcome == .exited(Data("C".utf8)))
    }
}
