import Foundation
@testable import StatusTrioCore

actor StubTelemetryTransport: TelemetryTransport {
    private(set) var requests: [URLRequest] = []
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private let statusCode: Int
    private let shouldThrow: Bool

    init(statusCode: Int = 204, shouldThrow: Bool = false) {
        self.statusCode = statusCode
        self.shouldThrow = shouldThrow
    }

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        requests.append(request)
        let ready = requestWaiters.filter { requests.count >= $0.0 }
        requestWaiters.removeAll { requests.count >= $0.0 }
        for (_, waiter) in ready { waiter.resume() }
        if shouldThrow { throw URLError(.timedOut) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            throw TelemetryTransportError.nonHTTPResponse
        }
        return response
    }

    func requestCount() -> Int { requests.count }
    func waitForRequestCount(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }
    func recordedRequests() -> [URLRequest] { requests }
}
