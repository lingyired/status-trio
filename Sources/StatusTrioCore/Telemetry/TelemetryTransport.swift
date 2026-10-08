import Foundation

protocol TelemetryTransport: Sendable {
    func send(request: URLRequest) async throws -> HTTPURLResponse
}

struct URLSessionTelemetryTransport: TelemetryTransport {
    private let session: URLSession

    init(configuration: TelemetryConfiguration) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.urlCache = nil
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.requestTimeout
        session = URLSession(configuration: sessionConfiguration)
    }

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw TelemetryTransportError.nonHTTPResponse }
        return httpResponse
    }
}

enum TelemetryTransportError: Error { case nonHTTPResponse }
