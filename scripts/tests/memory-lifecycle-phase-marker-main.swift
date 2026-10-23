import Foundation

@main
struct PhaseMarkerTestMain {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: phase-marker-test <phase-jsonl>\n", stderr)
            exit(64)
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        do {
            try writeFreshPhaseLog("launch", logURL: output)
            try appendPhaseLog("launch-appended", logURL: output)
        } catch {
            fputs("cannot write phase log: \(error)\n", stderr)
            exit(1)
        }
    }
}
