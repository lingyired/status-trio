import AppKit
import Foundation

private final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let phaseLogURL: URL
    private var window: NSWindow?

    init(phaseLogURL: URL) {
        self.phaseLogURL = phaseLogURL
    }

    private func recordOrTerminate(_ phase: String) {
        do {
            try appendPhaseLog(phase, logURL: phaseLogURL)
        } catch {
            fputs("cannot write phase \(phase): \(error)\n", stderr)
            exit(1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try writeFreshPhaseLog("launch", logURL: phaseLogURL)
        } catch {
            fputs("cannot write phase log: \(error)\n", stderr)
            exit(1)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "privacy-canary-window-title"
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.window?.orderFrontRegardless()
            self.recordOrTerminate("first-expand")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.window?.orderOut(nil)
            self.recordOrTerminate("close")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { [weak self] in
            guard let self else { return }
            self.window?.orderFrontRegardless()
            self.recordOrTerminate("reopen")
        }
    }
}

@main
struct WindowHarnessMain {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: memory-lifecycle-window-harness <phase-jsonl>\n", stderr)
            exit(64)
        }

        let phaseLogURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = HarnessDelegate(phaseLogURL: phaseLogURL)
        app.delegate = delegate
        app.run()
    }
}
