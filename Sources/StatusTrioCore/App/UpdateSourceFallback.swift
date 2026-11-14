import Foundation
import Sparkle

enum UpdateSource: Equatable, Sendable {
    case github
    case ghProxy
    case ghFast

    private var proxyPrefix: String? {
        switch self {
        case .github:
            nil
        case .ghProxy:
            "https://gh-proxy.com/"
        case .ghFast:
            "https://ghfast.top/"
        }
    }

    func url(for url: URL) -> URL {
        guard
            let proxyPrefix,
            Self.isGitHubURL(url),
            let proxiedURL = URL(string: proxyPrefix + url.absoluteString)
        else {
            return url
        }

        return proxiedURL
    }

    private static func isGitHubURL(_ url: URL) -> Bool {
        switch url.host?.lowercased() {
        case "github.com", "raw.githubusercontent.com":
            true
        default:
            false
        }
    }
}

struct UpdateSourceFallback {
    static let defaultSources: [UpdateSource] = [.github, .ghProxy, .ghFast]

    private let sources: [UpdateSource]
    private var attemptedSources: Set<UpdateSource> = []
    private(set) var currentSource: UpdateSource

    init(
        sources: [UpdateSource] = Self.defaultSources,
        initialSource: UpdateSource? = nil
    ) {
        let resolvedSources = sources.isEmpty ? Self.defaultSources : sources
        self.sources = resolvedSources
        self.currentSource = initialSource ?? resolvedSources[0]
    }

    func appcastURLString(from directURLString: String) -> String? {
        guard let directURL = URL(string: directURLString) else { return nil }
        return currentSource.url(for: directURL).absoluteString
    }

    func downloadURL(for appcastURL: URL) -> URL {
        currentSource.url(for: appcastURL)
    }

    func canAdvanceAfterError(_ error: Error?) -> Bool {
        guard UpdateSourceRetryPolicy.shouldTryNextSource(after: error) else {
            return false
        }

        guard
            let currentIndex = sources.firstIndex(of: currentSource),
            sources.indices.contains(currentIndex + 1)
        else {
            return false
        }

        return !attemptedSources.contains(sources[currentIndex + 1])
    }

    mutating func advanceAfterError(_ error: Error?) -> Bool {
        guard UpdateSourceRetryPolicy.shouldTryNextSource(after: error) else {
            attemptedSources.removeAll()
            return false
        }

        attemptedSources.insert(currentSource)

        guard
            let currentIndex = sources.firstIndex(of: currentSource),
            sources.indices.contains(currentIndex + 1)
        else {
            attemptedSources.removeAll()
            return false
        }

        let nextSource = sources[currentIndex + 1]
        guard !attemptedSources.contains(nextSource) else {
            attemptedSources.removeAll()
            return false
        }

        currentSource = nextSource
        return true
    }
}

private enum UpdateSourceRetryPolicy {
    static func shouldTryNextSource(after error: Error?) -> Bool {
        guard let error else { return false }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }

        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case Int(SUError.appcastError.rawValue),
                 Int(SUError.downloadError.rawValue):
                return true
            default:
                break
            }
        }

        guard let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error else {
            return false
        }

        return shouldTryNextSource(after: underlyingError)
    }
}
