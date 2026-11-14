import Foundation
import Sparkle
import Testing
@testable import StatusTrioCore

struct UpdateSourceFallbackTests {
    @Test
    func giteePreferenceIsScopedAndHasExactOrder() {
        #expect(UpdatePreference.githubFirst.sources == [.github, .gitee, .ghProxy, .ghFast])
        #expect(UpdatePreference.giteeFirst.sources == [.gitee, .github, .ghProxy, .ghFast])
        var fallback = UpdateSourceFallback(preference: .giteeFirst)
        #expect(fallback.currentSource == .gitee)
        let advanced = fallback.advanceAfterError(URLError(.timedOut))
        #expect(advanced)
        #expect(fallback.currentSource == .github)
        #expect(UpdateSourceFallback().currentSource == .github)
    }

    @Test
    func securityAndCancellationAreNeverRetriedEvenWhenWrapped() {
        for code in [URLError.cancelled, .secureConnectionFailed, .serverCertificateUntrusted, .userAuthenticationRequired, .badServerResponse, .cannotDecodeContentData] {
            let fallback = UpdateSourceFallback()
            let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue), userInfo: [NSUnderlyingErrorKey: URLError(code)])
            #expect(!fallback.canAdvanceAfterError(error))
        }
        let signature = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue), userInfo: [NSUnderlyingErrorKey: URLError(.timedOut)])
        #expect(!UpdateSourceFallback().canAdvanceAfterError(signature))
    }

    @Test
    func giteeFeedIsExplicitAndDownloadComesFromVerifiedFeed() {
        let fallback = UpdateSourceFallback(preference: .giteeFirst)
        #expect(fallback.appcastURLString(from: "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml") == "https://gitee.com/lingyired/status-trio/raw/main/appcast-gitee.xml")
        #expect(fallback.appcastURLString(from: "https://example.com/feed.xml") == "https://example.com/feed.xml")
        let attachment = URL(string: "https://gitee.com/lingyired/status-trio/attach_files/42/download/a.dmg")!
        #expect(fallback.downloadURL(for: attachment) == attachment)
    }

    @Test
    func directSourceKeepsGitHubURLsUnchanged() {
        let source = UpdateSource.github
        let appcastURL = URL(
            string: "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        )!
        let downloadURL = URL(
            string: "https://github.com/lingyired/status-trio/releases/download/v1.1.0/StatusTrio-1.1.0.dmg"
        )!

        #expect(source.url(for: appcastURL) == appcastURL)
        #expect(source.url(for: downloadURL) == downloadURL)
    }

    @Test
    func ghProxyPrefixesGitHubURLs() {
        let source = UpdateSource.ghProxy
        let appcastURL = URL(
            string: "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        )!
        let downloadURL = URL(
            string: "https://github.com/lingyired/status-trio/releases/download/v1.1.0/StatusTrio-1.1.0.dmg"
        )!

        #expect(
            source.url(for: appcastURL).absoluteString
                == "https://gh-proxy.com/https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        )
        #expect(
            source.url(for: downloadURL).absoluteString
                == "https://gh-proxy.com/https://github.com/lingyired/status-trio/releases/download/v1.1.0/StatusTrio-1.1.0.dmg"
        )
    }

    @Test
    func ghFastPrefixesGitHubURLs() {
        let source = UpdateSource.ghFast
        let appcastURL = URL(
            string: "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        )!

        #expect(
            source.url(for: appcastURL).absoluteString
                == "https://ghfast.top/https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        )
    }

    @Test
    func proxySourcesLeaveNonGitHubURLsUnchanged() {
        let source = UpdateSource.ghProxy
        let url = URL(string: "https://example.com/StatusTrio.dmg")!

        #expect(source.url(for: url) == url)
    }

    @Test
    func fallbackAdvancesThroughEverySourceOnce() {
        var fallback = UpdateSourceFallback(sources: [.github, .ghProxy, .ghFast], initialSource: .github)
        let error = URLError(.cannotConnectToHost)

        #expect(fallback.currentSource == .github)
        let advancedToProxy = fallback.advanceAfterError(error)
        #expect(advancedToProxy)
        #expect(fallback.currentSource == .ghProxy)
        let advancedToGhFast = fallback.advanceAfterError(error)
        #expect(advancedToGhFast)
        #expect(fallback.currentSource == .ghFast)
        let advancedPastGhFast = fallback.advanceAfterError(error)
        #expect(!advancedPastGhFast)
        #expect(fallback.currentSource == .ghFast)
    }

    @Test
    func fallbackCanAdvanceWithoutChangingSourceWhenNextSourceExists() {
        let fallback = UpdateSourceFallback(initialSource: .github)
        let error = URLError(.cannotConnectToHost)

        #expect(fallback.canAdvanceAfterError(error))
        #expect(fallback.currentSource == .github)
    }

    @Test
    func fallbackCannotAdvanceAfterLastSource() {
        let fallback = UpdateSourceFallback(initialSource: .ghFast)
        let error = URLError(.cannotConnectToHost)

        #expect(fallback.canAdvanceAfterError(error) == false)
        #expect(fallback.currentSource == .ghFast)
    }

    @Test
    func fallbackUsesSelectedSourceForFeedAndDownloadURLs() {
        let fallback = UpdateSourceFallback(initialSource: .ghFast)
        let appcastString = "https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        let downloadURL = URL(
            string: "https://github.com/lingyired/status-trio/releases/download/v1.1.0/StatusTrio-1.1.0.dmg"
        )!

        #expect(
            fallback.appcastURLString(from: appcastString)
                == "https://ghfast.top/https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml"
        )
        #expect(
            fallback.downloadURL(for: downloadURL).absoluteString
                == "https://ghfast.top/https://github.com/lingyired/status-trio/releases/download/v1.1.0/StatusTrio-1.1.0.dmg"
        )
    }

    @Test
    func fallbackAdvancesForSparkleDownloadErrors() {
        var fallback = UpdateSourceFallback(sources: [.github, .ghProxy, .ghFast], initialSource: .github)
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue))

        let advanced = fallback.advanceAfterError(error)
        #expect(advanced)
        #expect(fallback.currentSource == .ghProxy)
    }

    @Test
    func fallbackAdvancesForWrappedNetworkErrors() {
        var fallback = UpdateSourceFallback(sources: [.github, .ghProxy, .ghFast], initialSource: .github)
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [NSUnderlyingErrorKey: URLError(.timedOut)]
        )

        let advanced = fallback.advanceAfterError(error)
        #expect(advanced)
        #expect(fallback.currentSource == .ghProxy)
    }

    @Test
    func fallbackDoesNotAdvanceWhenNoUpdateWasFound() {
        var fallback = UpdateSourceFallback(initialSource: .github)
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))

        let advanced = fallback.advanceAfterError(error)
        #expect(!advanced)
        #expect(fallback.currentSource == .github)
    }

    @Test
    func fallbackDoesNotAdvanceForSignatureFailures() {
        var fallback = UpdateSourceFallback(initialSource: .github)
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue))

        let advanced = fallback.advanceAfterError(error)
        #expect(!advanced)
        #expect(fallback.currentSource == .github)
    }
}
