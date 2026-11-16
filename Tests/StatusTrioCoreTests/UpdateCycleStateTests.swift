import Foundation
import Sparkle
import Testing
@testable import StatusTrioCore

struct UpdateCycleStateTests {
    @Test
    func manualGiteeCycleEndsAndRestoresAutomaticDefault() {
        var cycle = UpdateCycleState()
        let first = cycle.beginManual(preference: .giteeFirst)
        #expect(first)
        #expect(cycle.appcastURLString(from: UpdateMirrorConfig.authoritativeAppcastURLString) == UpdateMirrorConfig.giteeAppcastURLString)
        cycle.finish()
        #expect(!cycle.isActive)
        #expect(cycle.preference == .githubFirst)
        #expect(cycle.appcastURLString(from: UpdateMirrorConfig.authoritativeAppcastURLString) == UpdateMirrorConfig.authoritativeAppcastURLString)
        let automatic = cycle.beginAutomaticIfIdle()
        #expect(automatic)
        #expect(cycle.preference == .githubFirst)
    }

    @Test
    func secondCycleAndAutomaticStartAreRejectedWhileActive() {
        var cycle = UpdateCycleState()
        let first = cycle.beginManual(preference: .giteeFirst)
        let second = cycle.beginManual(preference: .githubFirst)
        let automatic = cycle.beginAutomaticIfIdle()
        #expect(first)
        #expect(!second)
        #expect(!automatic)
        cycle.finish()
        let restarted = cycle.beginManual(preference: .githubFirst)
        #expect(restarted)
    }

    @Test
    func eachSourceIsTriedAtMostOnceAndCancelledNeverAdvances() {
        var cycle = UpdateCycleState()
        let began = cycle.beginManual(preference: .giteeFirst)
        #expect(began)
        let cancelled = cycle.advanceAfterError(URLError(.cancelled))
        #expect(!cancelled)
        let signature = cycle.advanceAfterError(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue)))
        #expect(!signature)
        let firstAdvance = cycle.advanceAfterError(URLError(.cannotFindHost))
        #expect(firstAdvance)
        #expect(cycle.fallback.currentSource == .github)
        let secondAdvance = cycle.advanceAfterError(URLError(.timedOut))
        #expect(secondAdvance)
        #expect(cycle.fallback.currentSource == .ghProxy)
        let thirdAdvance = cycle.advanceAfterError(URLError(.networkConnectionLost))
        #expect(thirdAdvance)
        #expect(cycle.fallback.currentSource == .ghFast)
        let exhausted = cycle.advanceAfterError(URLError(.timedOut))
        #expect(!exhausted)
    }

    @Test
    func sourceStaysFixedAcrossDownloadAndInstall() {
        var cycle = UpdateCycleState()
        let began = cycle.beginManual(preference: .giteeFirst)
        #expect(began)
        let feed = URL(string: UpdateMirrorConfig.giteeAppcastURLString)!
        cycle.markDownloading()
        #expect(cycle.downloadURL(for: feed) == feed)
        #expect(cycle.canSuppressErrorForRetry(URLError(.timedOut)))
        let duringDownload = cycle.advanceAfterError(URLError(.timedOut))
        #expect(!duringDownload)
        cycle.markInstalling()
        let duringInstall = cycle.advanceAfterError(URLError(.timedOut))
        #expect(!duringInstall)
        #expect(cycle.fallback.currentSource == .gitee)
        cycle.finish()
        #expect(cycle.fallback.currentSource == .github)
    }

    @Test
    func failedCycleRestartsFromGitHubNotLastFailedSource() {
        var cycle = UpdateCycleState()
        let began = cycle.beginManual(preference: .giteeFirst)
        #expect(began)
        let advanced = cycle.advanceAfterError(URLError(.timedOut))
        #expect(advanced)
        #expect(cycle.fallback.currentSource == .github)
        cycle.finish()
        let automatic = cycle.beginAutomaticIfIdle()
        #expect(automatic)
        #expect(cycle.fallback.currentSource == .github)
    }
}
