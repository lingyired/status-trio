import Foundation
import Testing
@testable import StatusTrioCore

/// A child that fills one pipe and then the other used to deadlock the runner:
/// `availableData` blocks on a pipe that is empty but still open, so a single
/// shared IO queue left the second stream's read waiting behind the first one's
/// block until the deadline killed the child. Both streams are read on their own
/// queue now, and these pin that.
///
/// Both payloads are past a pipe buffer (64 KB), which is the part that matters:
/// below it the child's writes fit in the kernel buffer and never wait for a
/// reader, so the deadlock cannot happen and the test would prove nothing.
struct BoundedProcessDualStreamTests {
    /// 150 KB per stream, with the sentinel as the last bytes written: a tail
    /// dropped by a half-drained pipe fails an equality check instead of
    /// quietly matching a shorter prefix.
    private static func payload(_ name: String) -> String {
        let filler = String(repeating: "x", count: 150_000)
        return filler + "|SENTINEL-\(name)"
    }

    @Test func finishesQuicklyWhenBothStreamsExceedAPipeBuffer() async throws {
        let script = try makeScript(stdout: Self.payload("out"), stderr: Self.payload("err"))
        defer { try? FileManager.default.removeItem(at: script) }

        // Ten seconds of deadline, and the assertion is that the invocation needs
        // a fraction of one: the only way to reach the deadline is the deadlock.
        // No sleep anywhere — the call returns when both streams have reached EOF.
        let started = ContinuousClock.now
        let outcome = await BoundedProcessInvocation.run(
            executableURL: script,
            arguments: [],
            timeout: .seconds(10)
        )
        let elapsed = ContinuousClock.now - started

        #expect(outcome == .exited(Data(Self.payload("out").utf8)))
        #expect(elapsed < .seconds(3), "took \(elapsed), which is the deadline path")
    }

    /// The blocking entry point the Wi-Fi and Bluetooth readers use, same shape.
    @Test func finishesQuicklyOnTheBlockingPathToo() async throws {
        let script = try makeScript(stdout: Self.payload("out"), stderr: Self.payload("err"))
        defer { try? FileManager.default.removeItem(at: script) }

        let started = ContinuousClock.now
        let outcome = BoundedProcessInvocation.runSync(
            executableURL: script,
            arguments: [],
            timeout: .seconds(10)
        )
        let elapsed = ContinuousClock.now - started

        #expect(outcome == .exited(Data(Self.payload("out").utf8)))
        #expect(elapsed < .seconds(3), "took \(elapsed), which is the deadline path")
    }

    /// `BoundedProcessOutcome` carries stdout only, so stderr is observed through
    /// the limiter: a stderr stream that is never read can never trip it. This is
    /// what keeps a future "just stop reading stderr" fix from passing the two
    /// tests above.
    @Test func readsStderrRatherThanIgnoringIt() async throws {
        let script = try makeScript(
            stdout: String(repeating: "o", count: 1_000),
            stderr: String(repeating: "e", count: 150_000)
        )
        defer { try? FileManager.default.removeItem(at: script) }

        let outcome = BoundedProcessInvocation.runSync(
            executableURL: script,
            arguments: [],
            timeout: .seconds(10),
            outputLimit: 100_000
        )

        #expect(outcome == .outputTooLarge)
    }

    /// Each payload is written to a file and `cat`-ed, so neither a shell
    /// argument length nor quoting rules are involved.
    private func makeScript(stdout stdoutPayload: String, stderr: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-stream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stdoutFile = directory.appendingPathComponent("stdout.txt")
        let stderrFile = directory.appendingPathComponent("stderr.txt")
        try Data(stdoutPayload.utf8).write(to: stdoutFile)
        try Data(stderr.utf8).write(to: stderrFile)

        let script = directory.appendingPathComponent("child.sh")
        let body = """
        #!/bin/sh
        set -e
        cat "\(stdoutFile.path)"
        cat "\(stderrFile.path)" >&2
        exit 0
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }
}
