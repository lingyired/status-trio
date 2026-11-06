import Darwin
import Foundation

/// A TUN that Mihomo itself reports. The device is the bridge between the
/// client's runtime configuration and the interfaces `getifaddrs` sees.
enum MihomoTunnelFailure: Equatable, Sendable {
    case requestRejected
    case failed
}

struct MihomoTunnelInfo: Equatable, Sendable {
    let provider: String
    let device: String
    let isEnabled: Bool
    var isChanging = false
    var failure: MihomoTunnelFailure?

    init(
        provider: String,
        device: String,
        isEnabled: Bool,
        isChanging: Bool = false,
        failure: MihomoTunnelFailure? = nil
    ) {
        self.provider = provider
        self.device = device
        self.isEnabled = isEnabled
        self.isChanging = isChanging
        self.failure = failure
    }
}

enum MihomoTunnelWriteResult: Equatable, Sendable {
    case updated(MihomoTunnelInfo)
    case rejected
    case failed
}

protocol MihomoTunnelReading: Sendable {
    func read() async -> MihomoTunnelInfo?
}

protocol MihomoTunnelControlling: MihomoTunnelReading {
    func setEnabled(_ enabled: Bool, expectedDevice: String) async -> MihomoTunnelWriteResult
}

/// Reads Clash Verge's Mihomo control socket. This is read-only: it never
/// sends PATCH and never changes the TUN. Local service-mode sockets are
/// owner-only; no administrator prompt or Accessibility grant is involved.
final class SystemMihomoTunnelClient: MihomoTunnelControlling, @unchecked Sendable {
    private let socketPaths: [(path: String, provider: String)]

    init(uid: uid_t = getuid()) {
        socketPaths = [
            (
                "/var/run/clash-verge-service/users/\(uid)/verge-mihomo.sock",
                "Clash Verge"
            )
        ]
    }

    func read() async -> MihomoTunnelInfo? {
        for candidate in socketPaths where FileManager.default.fileExists(atPath: candidate.path) {
            guard let json = await MihomoUnixHTTP.getJSON(path: "/configs", socketPath: candidate.path),
                  let info = MihomoConfigParser.tunnel(fromJSON: json, provider: candidate.provider) else {
                continue
            }
            return info
        }
        return nil
    }

    /// The provider/device check is repeated here, not only in the UI. A stale
    /// row must not toggle a different client's TUN after the user switches
    /// networks or clients.
    func setEnabled(_ enabled: Bool, expectedDevice: String) async -> MihomoTunnelWriteResult {
        for candidate in socketPaths where FileManager.default.fileExists(atPath: candidate.path) {
            guard let before = await MihomoUnixHTTP.getJSON(path: "/configs", socketPath: candidate.path),
                  let current = MihomoConfigParser.tunnel(fromJSON: before, provider: candidate.provider),
                  current.device == expectedDevice else {
                continue
            }
            let body = try? JSONSerialization.data(withJSONObject: ["tun": ["enable": enabled]])
            guard let body,
                  await MihomoUnixHTTP.patch(path: "/configs", body: body, socketPath: candidate.path) else {
                return .rejected
            }
            guard let after = await MihomoUnixHTTP.getJSON(path: "/configs", socketPath: candidate.path),
                  let updated = MihomoConfigParser.tunnel(fromJSON: after, provider: candidate.provider),
                  updated.device == expectedDevice,
                  updated.isEnabled == enabled else {
                return .failed
            }
            return .updated(updated)
        }
        return .rejected
    }
}

enum MihomoConfigParser {
    static func tunnel(fromJSON json: [String: Any], provider: String) -> MihomoTunnelInfo? {
        guard let tun = json["tun"] as? [String: Any],
              let device = tun["device"] as? String,
              !device.isEmpty else {
            return nil
        }
        return MihomoTunnelInfo(
            provider: provider,
            device: device,
            isEnabled: tun["enable"] as? Bool == true
        )
    }
}

private enum MihomoUnixHTTP {
    static func getJSON(path: String, socketPath: String) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let data = request(method: "GET", path: path, body: nil, socketPath: socketPath),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: object)
            }
        }
    }

    static func patch(path: String, body: Data, socketPath: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: request(method: "PATCH", path: path, body: body, socketPath: socketPath) != nil
                )
            }
        }
    }

    private static func request(
        method: String,
        path: String,
        body: Data?,
        socketPath: String
    ) -> Data? {
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { return nil }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { destination in
                for (index, byte) in bytes.enumerated() {
                    destination[index] = CChar(bitPattern: byte)
                }
                destination[bytes.count] = 0
            }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let bodyLength = body?.count ?? 0
        var request = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
        if body != nil {
            request += "Content-Type: application/json\r\nContent-Length: \(bodyLength)\r\n"
        }
        request += "\r\n"
        var requestData = Data(request.utf8)
        if let body { requestData.append(body) }
        let sent = requestData.withUnsafeBytes { buffer in
            send(fd, buffer.baseAddress, requestData.count, 0)
        }
        guard sent == requestData.count else { return nil }

        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let read = buffer.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress, raw.count, 0)
            }
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
            if data.count > 1_000_000 { return nil }
        }
        guard let text = String(bytes: data, encoding: .utf8),
              let separator = text.range(of: "\r\n\r\n"),
              text.hasPrefix("HTTP/1.1 2") else {
            return nil
        }
        return Data(text[separator.upperBound...].utf8)
    }
}
