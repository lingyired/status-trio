import Foundation

func writeFreshPhaseLog(
    _ name: String,
    logURL: URL,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
) throws {
    let object: [String: Any] = [
        "phase": name,
        "timestamp": NSNumber(value: clock()),
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    try (data + Data([0x0a])).write(to: logURL, options: .withoutOverwriting)
}
func appendPhaseLog(
    _ name: String,
    logURL: URL,
    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
) throws {
    let object: [String: Any] = [
        "phase": name,
        "timestamp": NSNumber(value: clock()),
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: data + Data([0x0a]))
    try handle.synchronize()
    try handle.close()
}
