import Foundation

struct AirPodsAudioHelper {
    struct Snapshot: Decodable, Equatable { let conversation: Bool? }

    static func run(uid: String, conversation: Bool? = nil) async throws -> Snapshot {
        try Task.checkCancellation()
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/StatusTrioAirPodsHelper")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw AirPodsSystemControlError.unavailable }
        let operation = conversation.map { $0 ? "ca-on" : "ca-off" } ?? "read"
        let result = await BoundedProcessInvocation.run(executableURL: executable,
            arguments: [operation, uid], timeout: .seconds(5), outputLimit: 4096)
        try Task.checkCancellation()
        guard case let .exited(data) = result else { throw AirPodsSystemControlError.unavailable }
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }
}
