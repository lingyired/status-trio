import Darwin
import Foundation
import Testing
@testable import StatusTrioCore

/// The shared runner reads both pipes again after the child is gone, then drains
/// them to EOF. `main` gained that in #131 because a helper report arrived
/// truncated: the tail of a JSON payload is not a status code, so losing it
/// surfaces as a decode failure three layers away from the cause, and nothing
/// about it looks like a timing bug.
///
/// The fixture that provokes it is the one a real helper produces by accident: a
/// child that writes its report and exits while a descendant still holds the
/// inherited write ends. The payload is larger than a pipe buffer, so it cannot
/// be sitting in the pipe by luck when the child exits - it has to be read, and
/// the descendant only releases the pipe when this test says so. No fixed sleeps:
/// the test waits on the child's exit (via `kill(pid, 0)`) and then signals the
/// descendant through a FIFO.
struct BoundedProcessDrainTests {
    /// Roughly 150 KB: well past the 64 KB pipe buffer, with a sentinel at the
    /// very end so a truncated tail is unmissable rather than a shorter string.
    static let payload: String = {
        let filler = Array(
            repeating: #"{"id":"AA:BB:CC:DD:EE:FF","battery":{"single":97}},"#,
            count: 3_000
        ).joined()
        return #"{"schema":"status-trio.helper.v1","devices":["# + filler + #"],"end":"SENTINEL-TAIL"}"#
    }()

    @Test func keepsTheWholeReportWhenADescendantOutlivesTheChild() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        async let outcome = BoundedProcessInvocation.run(
            executableURL: fixture.script,
            arguments: fixture.arguments,
            timeout: .seconds(20)
        )

        try await fixture.waitForChildExit()
        fixture.releaseHeldStreams()
        let result = await outcome

        #expect(result == .exited(Data(Self.payload.utf8)))
    }

    /// The path T-9 and T-10 take: `runSync` blocks the caller, so the release
    /// has to come from another thread. Same fixture, same expectation.
    @Test func keepsTheWholeReportOnTheBlockingPathToo() async throws {
        let fixture = try HeldStreamFixture(stream: .stdout)
        defer { fixture.cleanUp() }

        let release = Task.detached {
            try await fixture.waitForChildExit()
            fixture.releaseHeldStreams()
        }

        let result = BoundedProcessInvocation.runSync(
            executableURL: fixture.script,
            arguments: fixture.arguments,
            timeout: .seconds(20)
        )
        try? await release.value

        #expect(result == .exited(Data(Self.payload.utf8)))
    }

}

/// Runs a child that writes `BoundedProcessDrainTests.payload`, records its own
/// pid, and exits while a descendant keeps the inherited write ends open.
private struct HeldStreamFixture {
    enum Stream {
        /// The report goes to stdout, which the outcome carries.
        case stdout
        /// The same report goes to stderr as well, so the stderr drain runs too.
        case both
    }

    let script: URL
    let arguments: [String]

    private let pidFile: URL
    private let gate: URL
    private let payloadFile: URL
    private let directory: URL

    init(stream: Stream) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("drain-eos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        payloadFile = directory.appendingPathComponent("payload.json")
        pidFile = directory.appendingPathComponent("child.pid")
        gate = directory.appendingPathComponent("gate.fifo")
        script = directory.appendingPathComponent("child.sh")

        try Data(BoundedProcessDrainTests.payload.utf8).write(to: payloadFile)
        guard mkfifo(gate.path, 0o600) == 0 else {
            throw FixtureError.couldNotCreateFIFO(errno)
        }

        // The descendant inherits fd 1 and 2 and blocks on the FIFO, so the child
        // can exit while the write ends are still open. `set -e` keeps a failed
        // write from looking like a clean exit.
        let stderrLine = stream == .both ? #"cat "\#(payloadFile.path)" >&2"# : ""
        let body = """
        #!/bin/sh
        set -e
        ( read _held < "\(gate.path)"; exit 0 ) &
        cat "\(payloadFile.path)"
        \(stderrLine)
        echo $$ > "\(pidFile.path)"
        exit 0
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        arguments = []
    }

    enum FixtureError: Error {
        case couldNotCreateFIFO(Int32)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Waits until the child process is gone, without a fixed sleep: poll the pid
    /// it published, and treat `ESRCH` as the exit.
    func waitForChildExit() async throws {
        for _ in 0..<500 {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                errno = 0
                if kill(pid, 0) == -1, errno == ESRCH { return }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("child process never exited")
    }

    /// Closes the descendant's blocking read, which closes the inherited write
    /// ends and lets the runner reach EOF.
    func releaseHeldStreams() {
        // O_RDWR so opening the FIFO cannot block on the reader or the writer.
        let descriptor = open(gate.path, O_RDWR)
        guard descriptor >= 0 else {
            Issue.record("could not open the release FIFO: errno \(errno)")
            return
        }
        defer { close(descriptor) }
        var newline = UInt8(ascii: "\n")
        _ = write(descriptor, &newline, 1)
    }
}
