import Foundation

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
