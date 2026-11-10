import Foundation

struct BetterDisplayFramebufferIdentity: Equatable, Sendable {
    let registryLocation: String
    let edidUUID: String?
}

enum BetterDisplayAudioDisplayMatcher {
    static func match(
        outputUID: String,
        framebuffers: [BetterDisplayFramebufferIdentity],
        devices: [BetterDisplayDevice]
    ) -> String? {
        guard !outputUID.isEmpty else { return nil }
        let frames = framebuffers.filter { $0.edidUUID == outputUID }
        guard frames.count == 1, let frame = frames.first,
              !frame.registryLocation.isEmpty else { return nil }
        let matches = devices.filter { $0.registryLocation == frame.registryLocation }
        guard matches.count == 1, let match = matches.first,
              !match.uuid.isEmpty else { return nil }
        return match.uuid
    }
}
