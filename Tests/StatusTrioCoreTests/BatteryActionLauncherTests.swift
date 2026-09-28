import Foundation
import XCTest

@testable import StatusTrioCore

@MainActor
final class BatteryActionLauncherTests: XCTestCase {
    func testSystemTargetUsesOnlyTheSystemSettingsFallback() async {
        let workspace = FakeBatteryWorkspace()
        var fallbackCount = 0

        await BatteryActionLauncher(workspace: workspace).open(target: .systemSettings) {
            fallbackCount += 1
        }

        XCTAssertEqual(workspace.events, [])
        XCTAssertEqual(fallbackCount, 1)
    }

    func testKnownAppDetectionReflectsInstalledApplications() {
        let workspace = FakeBatteryWorkspace()
        let alDenteURL = appURL("/Applications/AlDente.app")
        workspace.applicationURLs["com.apphousekitchen.aldente-pro"] = alDenteURL
        workspace.existingApplicationPaths = [alDenteURL.path]
        let launcher = BatteryActionLauncher(workspace: workspace)

        XCTAssertTrue(launcher.isInstalled(KnownBatteryApps.definition(for: .alDente)))
        XCTAssertFalse(launcher.isInstalled(KnownBatteryApps.definition(for: .batFi)))
    }

    func testKnownAppOpensInstalledDeepLinkBeforeLaunchingApplication() async throws {
        let deepLink = try XCTUnwrap(URL(string: "aldente-test://open"))
        let definition = KnownBatteryAppDefinition(
            id: .alDente,
            displayName: "AlDente",
            bundleIdentifiers: ["com.example.AlDente"],
            deepLink: deepLink
        )
        let workspace = FakeBatteryWorkspace()
        let applicationURL = appURL("/Applications/AlDente.app")
        workspace.applicationURLs["com.example.AlDente"] = applicationURL
        workspace.existingApplicationPaths = [applicationURL.path]
        var fallbackCount = 0

        await BatteryActionLauncher(workspace: workspace, definitions: [definition])
            .open(target: .knownApp(.alDente)) { fallbackCount += 1 }

        XCTAssertEqual(workspace.events, [
            "resolve:com.example.AlDente",
            "exists:\(applicationURL.path)",
            "open-url:\(deepLink.absoluteString)"
        ])
        XCTAssertEqual(workspace.openedApplications, [])
        XCTAssertEqual(fallbackCount, 0)
    }

    func testFailedKnownAppDeepLinkFallsThroughToApplicationLaunch() async throws {
        let deepLink = try XCTUnwrap(URL(string: "aldente-test://open"))
        let definition = KnownBatteryAppDefinition(
            id: .alDente,
            displayName: "AlDente",
            bundleIdentifiers: ["com.example.AlDente"],
            deepLink: deepLink
        )
        let workspace = FakeBatteryWorkspace()
        let applicationURL = appURL("/Applications/AlDente.app")
        workspace.applicationURLs["com.example.AlDente"] = applicationURL
        workspace.existingApplicationPaths = [applicationURL.path]
        workspace.urlOpenResults[deepLink] = false

        await BatteryActionLauncher(workspace: workspace, definitions: [definition])
            .open(target: .knownApp(.alDente)) {}

        XCTAssertEqual(workspace.events, [
            "resolve:com.example.AlDente",
            "exists:\(applicationURL.path)",
            "open-url:\(deepLink.absoluteString)",
            "launch:\(applicationURL.path)"
        ])
        XCTAssertEqual(workspace.openedApplications, [applicationURL])
    }

    func testKnownAppLaunchFailureFallsBackToSystemSettings() async {
        let workspace = FakeBatteryWorkspace()
        let applicationURL = appURL("/Applications/BatFi.app")
        workspace.applicationURLs["software.micropixels.BatFi"] = applicationURL
        workspace.existingApplicationPaths = [applicationURL.path]
        workspace.failedApplicationPaths = [applicationURL.path]
        var fallbackCount = 0

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .knownApp(.batFi)) { fallbackCount += 1 }

        XCTAssertEqual(workspace.openedApplications, [applicationURL])
        XCTAssertEqual(workspace.events.last, "launch:\(applicationURL.path)")
        XCTAssertEqual(fallbackCount, 1)
    }

    func testCustomAppUsesBundleIdentifierToRelocateApplication() async {
        let workspace = FakeBatteryWorkspace()
        let movedURL = appURL("/Users/tester/Applications/Tool.app")
        workspace.applicationURLs["com.example.Tool"] = movedURL
        workspace.existingApplicationPaths = [movedURL.path]

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .customApp(.init(
                displayName: "Tool",
                bundleIdentifier: "com.example.Tool",
                fallbackPath: "/Applications/Old Tool.app"
            ))) {}

        XCTAssertEqual(workspace.openedApplications, [movedURL])
        XCTAssertEqual(workspace.events.first, "resolve:com.example.Tool")
    }

    func testCustomAppUsesExistingFallbackPathWhenBundleIdentifierCannotResolve() async {
        let workspace = FakeBatteryWorkspace()
        let fallbackURL = appURL("/Applications/Tool.app")
        workspace.existingApplicationPaths = [fallbackURL.path]

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .customApp(.init(
                displayName: "Tool",
                bundleIdentifier: "com.example.Tool",
                fallbackPath: fallbackURL.path
            ))) {}

        XCTAssertEqual(workspace.openedApplications, [fallbackURL])
        XCTAssertEqual(workspace.events.first, "resolve:com.example.Tool")
    }

    func testUnavailableOrMalformedCustomAppFallsBackToSystemSettings() async {
        let workspace = FakeBatteryWorkspace()
        var fallbackCount = 0

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .customApp(.init(
                displayName: "Saved Tool",
                bundleIdentifier: " \n ",
                fallbackPath: "/Applications/Missing.app"
            ))) { fallbackCount += 1 }

        XCTAssertFalse(workspace.events.contains { $0.hasPrefix("resolve:") })
        XCTAssertEqual(workspace.openedApplications, [])
        XCTAssertEqual(fallbackCount, 1)
    }

    func testSameResolvedAndFallbackApplicationIsLaunchedOnlyOnceAfterFailure() async {
        let workspace = FakeBatteryWorkspace()
        let applicationURL = appURL("/Applications/Tool.app")
        workspace.applicationURLs["com.example.Tool"] = applicationURL
        workspace.existingApplicationPaths = [applicationURL.path]
        workspace.failedApplicationPaths = [applicationURL.path]
        var fallbackCount = 0

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .customApp(.init(
                displayName: "Tool",
                bundleIdentifier: "com.example.Tool",
                fallbackPath: applicationURL.path
            ))) { fallbackCount += 1 }

        XCTAssertEqual(workspace.openedApplications, [applicationURL])
        XCTAssertEqual(fallbackCount, 1)
    }

    func testFailedPrimaryLaunchAdvancesToDistinctSavedFallbackPath() async {
        let workspace = FakeBatteryWorkspace()
        let resolvedURL = appURL("/Applications/Moved Tool.app")
        let fallbackURL = appURL("/Applications/Saved Tool.app")
        workspace.applicationURLs["com.example.Tool"] = resolvedURL
        workspace.existingApplicationPaths = [resolvedURL.path, fallbackURL.path]
        workspace.failedApplicationPaths = [resolvedURL.path]

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .customApp(.init(
                displayName: "Tool",
                bundleIdentifier: "com.example.Tool",
                fallbackPath: fallbackURL.path
            ))) {}

        XCTAssertEqual(workspace.openedApplications, [resolvedURL, fallbackURL])
        XCTAssertEqual(workspace.events.filter { $0.hasPrefix("launch:") }, [
            "launch:\(resolvedURL.path)",
            "launch:\(fallbackURL.path)"
        ])
    }

    func testURLValidationTrimsOuterWhitespaceAndRequiresAScheme() throws {
        let url = try XCTUnwrap(BatteryActionLauncher.validatedURL("  raycast://battery/open?name=two%20words \n"))

        XCTAssertEqual(url.absoluteString, "raycast://battery/open?name=two%20words")
        XCTAssertNil(BatteryActionLauncher.validatedURL("example.com/path"))
        XCTAssertNil(BatteryActionLauncher.validatedURL(" \n "))
    }

    func testCustomURLOpenFailureFallsBackToSystemSettings() async throws {
        let workspace = FakeBatteryWorkspace()
        let url = try XCTUnwrap(URL(string: "custom+test://battery/open"))
        workspace.urlOpenResults[url] = false
        var fallbackCount = 0

        await BatteryActionLauncher(workspace: workspace)
            .open(target: .customURL(url.absoluteString)) { fallbackCount += 1 }

        XCTAssertEqual(workspace.openedURLs, [url])
        XCTAssertEqual(fallbackCount, 1)
    }

    private func appURL(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }
}

@MainActor
private final class FakeBatteryWorkspace: BatteryWorkspace {
    var applicationURLs: [String: URL] = [:]
    var existingApplicationPaths: Set<String> = []
    var failedApplicationPaths: Set<String> = []
    var urlOpenResults: [URL: Bool] = [:]
    private(set) var openedApplications: [URL] = []
    private(set) var openedURLs: [URL] = []
    private(set) var events: [String] = []

    func applicationURL(bundleIdentifier: String) -> URL? {
        events.append("resolve:\(bundleIdentifier)")
        return applicationURLs[bundleIdentifier]
    }

    func fileExists(at url: URL) -> Bool {
        events.append("exists:\(url.path)")
        return existingApplicationPaths.contains(url.standardizedFileURL.path)
    }

    func openURL(_ url: URL) -> Bool {
        events.append("open-url:\(url.absoluteString)")
        openedURLs.append(url)
        return urlOpenResults[url] ?? true
    }

    func openApplication(_ url: URL) async throws {
        events.append("launch:\(url.standardizedFileURL.path)")
        openedApplications.append(url)
        if failedApplicationPaths.contains(url.standardizedFileURL.path) {
            throw TestLaunchError.failed
        }
    }

    private enum TestLaunchError: Error {
        case failed
    }
}
