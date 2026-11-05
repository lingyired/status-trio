import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func command(_ executable: String, _ arguments: [String]) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    let output = Pipe()
    task.standardOutput = output
    do { try task.run() } catch { fail("\(executable): \(error)") }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fail("\(executable) exited \(task.terminationStatus)") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard (arguments.count == 3 && arguments[0] == "prepare")
        || ((["launch", "reuse"].contains(arguments[0]))
            && (arguments.count == 4 || arguments.count == 5)
            && ["automatic", "secondary"].contains(arguments[3])
            && (arguments.count == 4 || ["settings", "panel"].contains(arguments[4]))),
      arguments[1].hasPrefix("com.lingsmbp.StatusTrio.dev.") else {
    fail("Usage: computer-use-instance.swift <prepare|launch|reuse> <dev-bundle-id> <app-path> [automatic|secondary] [settings|panel]")
}
let mode = arguments[0]
let bundleID = arguments[1]
let appURL = URL(fileURLWithPath: arguments[2]).resolvingSymlinksInPath()
let executableURL = appURL.appendingPathComponent("Contents/MacOS/StatusTrio").resolvingSymlinksInPath()

func instances() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
}

func validatePath(_ app: NSRunningApplication) {
    guard app.bundleURL?.resolvingSymlinksInPath() == appURL,
          app.executableURL?.resolvingSymlinksInPath() == executableURL else {
        fail("Bundle ID collision at PID \(app.processIdentifier); another checkout will not be touched.")
    }
}

func launchArguments(_ app: NSRunningApplication) -> [Substring] {
    command("/bin/ps", ["-ww", "-p", String(app.processIdentifier), "-o", "args="])
        .split(whereSeparator: \.isWhitespace)
}

func requestedPanelMode() -> String {
    arguments.count == 5 ? arguments[4] : "settings"
}

func report(_ app: NSRunningApplication, launchToken: String, display: String, reused: Bool) {
    let panelMode = requestedPanelMode()
    let plist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) ?? [:]
    let report: [String: Any] = [
        "bundleID": bundleID, "path": appURL.path, "pid": app.processIdentifier,
        "sha": plist["STBuildCommit"] ?? "", "sourceDirty": plist["STBuildSourceDirty"] ?? false,
        "backgroundUITesting": true, "requestedDisplay": display,
        "requestedStatusPanel": panelMode == "panel",
        "launchToken": launchToken, "reused": reused,
        "mainDisplayID": CGMainDisplayID(),
        "connectedDisplayIDs": NSScreen.screens.map {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        }
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else {
        fail("Could not encode instance identity.")
    }
    print(String(decoding: data, as: UTF8.self))
}

if mode == "prepare" {
    let running = instances()
    guard running.count <= 1 else { fail("Multiple instances share \(bundleID); stop and inspect them.") }
    if let app = running.first {
        validatePath(app)
        fail("PID \(app.processIdentifier) is already running and will not be stopped. Use --reuse for a suitable test instance, or have its owner close it before rebuilding.")
    }
} else if mode == "reuse" {
    let running = instances()
    guard running.count == 1, let app = running.first, app.isFinishedLaunching else {
        fail("Reuse needs exactly one finished test instance; no launch or reopen was sent.")
    }
    validatePath(app)
    let actualArguments = launchArguments(app)
    let tokens = actualArguments.filter { $0.hasPrefix("--status-trio-ui-test-launch=") }
    let plist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) ?? [:]
    guard actualArguments.contains("--background-ui-testing"),
          tokens.count == 1, let token = tokens.first,
          UUID(uuidString: String(token.dropFirst("--status-trio-ui-test-launch=".count))) != nil,
          plist["CFBundleIdentifier"] as? String == bundleID,
          plist["STBackgroundUITestingSupported"] as? Bool == true else {
        fail("Existing instance lacks the expected Debug test identity and launch token.")
    }
    let display = actualArguments.contains("--test-display=secondary") ? "secondary" : "automatic"
    guard arguments[3] != "secondary" || display == "secondary" else {
        fail("Existing instance did not request the secondary display; reuse will not move its windows.")
    }
    let hasStatusPanel = actualArguments.contains("--test-open-status-panel")
    guard (requestedPanelMode() == "panel") == hasStatusPanel else {
        fail("Existing instance status-panel mode does not match the requested reuse mode.")
    }
    report(app, launchToken: String(token), display: display, reused: true)
} else {
    // Recheck after the build: another launch may have occurred in the meantime.
    guard instances().isEmpty else { fail("An instance appeared during build; no reopen or duplicate launch sent.") }
    var flags = ["--background-ui-testing"]
    if arguments[3] == "secondary" { flags.append("--test-display=secondary") }
    if requestedPanelMode() == "panel" { flags.append("--test-open-status-panel") }
    // A process racing a manual launch must not be reported as this launch.
    let launchToken = "--status-trio-ui-test-launch=\(UUID().uuidString)"
    flags.append(launchToken)
    _ = command("/usr/bin/open", ["-g", "-a", appURL.path, "--args"] + flags)
    let deadline = Date(timeIntervalSinceNow: 8)
    var launched: NSRunningApplication?
    while Date() < deadline {
        let running = instances()
        guard running.count <= 1 else { fail("Unexpected duplicate launch; inspect \(bundleID).") }
        if let app = running.first, app.isFinishedLaunching {
            launched = app
            break
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    guard let app = launched else { fail("No running test instance after launch; inspect SingleInstance logs.") }
    validatePath(app)
    let actualArguments = launchArguments(app)
    guard flags.allSatisfy({ actualArguments.contains(Substring($0)) }) else {
        fail("Running PID \(app.processIdentifier) does not have the requested test arguments.")
    }
    report(app, launchToken: launchToken, display: arguments[3], reused: false)
}
