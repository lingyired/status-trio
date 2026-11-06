import Darwin
import Foundation

/// A TUN that Mihomo itself reports. The device is the bridge between the
/// client's runtime configuration and the interfaces `getifaddrs` sees.
struct MihomoTunnelInfo: Equatable, Sendable {
    let provider: String
    let device: String
    let isEnabled: Bool
}

protocol MihomoTunnelReading: Sendable {
    func read() async -> MihomoTunnelInfo?
}

/// Reads Clash Verge's Mihomo control socket. This is read-only: it never
/// sends PATCH and never changes the TUN. Local service-mode sockets are
/// owner-only; no administrator prompt or Accessibility grant is involved.
final class SystemMihomoTunnelClient: MihomoTunnelReading, @unchecked Sendable {
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
            guard let json = await MihomoUnixHTTP.get(path: "/configs", socketPath: candidate.path),
                  let info = MihomoConfigParser.tunnel(fromJSON: json, provider: candidate.provider) else {
                continue
            }
            return info
        }
        return nil
    }
}

enum MihomoConfigParser {
    static func tunnel(fromJSON json: [String: Any], provider: String) -> MihomoTunnelInfo? {
        guard let tun = json["tun"] as? [String: Any],
              tun["enable"] as? Bool == true,
              let device = tun["device"] as? String,
              !device.isEmpty else {
            return nil
        }
        return MihomoTunnelInfo(provider: provider, device: device, isEnabled: true)
    }
}

private enum MihomoUnixHTTP {
    static func get(path: String, socketPath: String) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: getSync(path: path, socketPath: socketPath))
            }
        }
    }

    private static func getSync(path: String, socketPath: String) -> [String: Any]? {
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

        let request = "GET \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        let sent = request.utf8CString.withUnsafeBytes { buffer in
            send(fd, buffer.baseAddress, request.utf8.count, 0)
        }
        guard sent == request.utf8.count else { return nil }

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
              text.hasPrefix("HTTP/1.1 200") else {
            return nil
        }
        let body = String(text[separator.upperBound...])
        return try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
    }
}
