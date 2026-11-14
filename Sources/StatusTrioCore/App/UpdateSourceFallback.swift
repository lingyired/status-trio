import Foundation
import Sparkle

enum UpdateSource: Equatable, Sendable {
    case github
    case gitee
    case ghProxy
    case ghFast

    private var proxyPrefix: String? {
        switch self {
        case .github, .gitee:
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

enum UpdatePreference: Sendable, Equatable {
    case githubFirst
    case giteeFirst

    var sources: [UpdateSource] {
        switch self {
        case .githubFirst:
            [.github, .gitee, .ghProxy, .ghFast]
        case .giteeFirst:
            [.gitee, .github, .ghProxy, .ghFast]
        }
    }
}

enum UpdateMirrorConfig {
    static let giteeRepository = "lingyired/status-trio"
    static let authoritativeAppcastURLString =
        "https://raw.githubusercontent.com/\(giteeRepository)/main/appcast.xml"
    static let giteeAppcastURLString =
        "https://gitee.com/\(giteeRepository)/raw/main/appcast-gitee.xml"

    /// Only the project's authoritative appcast is rewritten. Arbitrary URLs are
    /// never turned into Gitee URLs.
    static func giteeAppcastURL(from directURL: URL) -> URL {
        guard directURL.absoluteString == authoritativeAppcastURLString,
              let mirror = URL(string: giteeAppcastURLString)
        else {
            return directURL
        }
        return mirror
    }
}

struct UpdateSourceFallback {
    static let defaultSources: [UpdateSource] = UpdatePreference.githubFirst.sources

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

    init(preference: UpdatePreference) {
        self.init(sources: preference.sources)
    }

    func appcastURLString(from directURLString: String) -> String? {
        guard let directURL = URL(string: directURLString) else { return nil }
        let resolvedURL = currentSource == .gitee
            ? UpdateMirrorConfig.giteeAppcastURL(from: directURL)
            : currentSource.url(for: directURL)
        return resolvedURL.absoluteString
    }

    func downloadURL(for appcastURL: URL) -> URL {
        // A Gitee appcast already contains absolute Gitee attachment URLs (and
        // authoritative GitHub URLs for unmirrored history). Never proxy it.
        if currentSource == .gitee {
            return appcastURL
        }
        return currentSource.url(for: appcastURL)
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
            return false
        }

        let nextSource = sources[currentIndex + 1]
        guard !attemptedSources.contains(nextSource) else { return false }
        currentSource = nextSource
        return true
    }

    mutating func reset() {
        attemptedSources.removeAll()
        currentSource = sources[0]
    }
}

private enum UpdateSourceRetryPolicy {
    /// Deliberately an allowlist: only transient network failures can move on.
    /// Cancellation, TLS/security failures, signature failures and install
    /// failures must surface to the user without touching another source.
    static func shouldTryNextSource(after error: Error?) -> Bool {
        guard let error else { return false }
        return isRetryable(error)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .cannotFindHost,
                 .dnsLookupFailed,
                 .timedOut,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }

        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case Int(SUError.appcastError.rawValue),
                 Int(SUError.downloadError.rawValue):
                // A retryable Sparkle phase still has to carry a retryable
                // network cause; a signature or install cause never does.
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                    return isRetryable(underlying)
                }
                return true
            default:
                return false
            }
        }

        guard let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error else {
            return false
        }
        return isRetryable(underlyingError)
    }
}
