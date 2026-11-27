import XCTest
@testable import StatusTrioCore

final class ProcessAppResolverTests: XCTestCase {
    private let browser = ProcessApplication(pid: 100, path: "/Applications/Browser.app",
                                             bundleID: "com.example.browser", name: "Browser")
    private let editor = ProcessApplication(pid: 200, path: "/Applications/Editor.app",
                                            bundleID: "com.example.editor", name: "Editor")

    private func metadata(_ pid: Int32,
                          start: UInt64 = 1,
                          name: String,
                          path: String?,
                          responsible: Int32? = nil,
                          parent: Int32? = nil) -> ProcessMetadata {
        ProcessMetadata(identity: ProcessIdentity(pid: pid, startedAt: start),
                        name: name, executablePath: path,
                        responsiblePID: responsible, parentPID: parent)
    }

    func testResponsiblePIDWinsForHelper() {
        let helper = metadata(300, name: "Browser Helper", path: "/Applications/Browser.app/Contents/Helpers/Browser Helper", responsible: 100)
        let result = ProcessAppResolver.resolve(helper, applications: [browser, editor])
        XCTAssertEqual(result.identity, .application(path: "/Applications/Browser.app"))
        XCTAssertEqual(result.name, "Browser")
    }

    func testExactAppPIDMatches() {
        let app = metadata(200, name: "Editor", path: "/Applications/Editor.app/Contents/MacOS/Editor")
        let result = ProcessAppResolver.resolve(app, applications: [browser, editor])
        XCTAssertEqual(result.identity, .application(path: "/Applications/Editor.app"))
        XCTAssertEqual(result.name, "Editor")
    }

    func testNestedHelperCollapsesIntoOuterBundleWithoutRunningAppRow() {
        let helper = metadata(300, name: "Nested Helper",
                              path: "/Applications/Browser.app/Contents/Helpers/Nested.app/Contents/MacOS/Nested")
        let result = ProcessAppResolver.resolve(helper, applications: [])
        XCTAssertEqual(result.identity, .application(path: "/Applications/Browser.app"))
        XCTAssertEqual(result.name, "Browser")
    }

    func testParentChainFallbackFindsRunningApp() {
        let child = metadata(300, name: "External XPC", path: "/Library/XPCServices/External.xpc/Contents/MacOS/External",
                             parent: 100)
        let result = ProcessAppResolver.resolve(
            child,
            applications: [browser],
            parentMetadata: { pid in
                pid == 100 ? self.metadata(100, name: "Browser", path: "/Applications/Browser.app/Contents/MacOS/Browser") : nil
            }
        )
        XCTAssertEqual(result.identity, .application(path: "/Applications/Browser.app"))
        XCTAssertEqual(result.name, "Browser")
    }

    func testSimilarBundlePrefixIsNotMerged() {
        let process = metadata(300, name: "Other", path: "/Applications/BrowserSibling.app/Contents/MacOS/Other")
        let result = ProcessAppResolver.resolve(process, applications: [browser])
        XCTAssertEqual(result.identity, .application(path: "/Applications/BrowserSibling.app"))
        XCTAssertNotEqual(result.identity, .application(path: "/Applications/Browser.app"))
    }

    func testSameNameDifferentPathsStaySeparate() {
        let otherBrowser = ProcessApplication(pid: 400, path: "/Applications/Other/Browser.app",
                                              bundleID: "com.example.other-browser", name: "Browser")
        let process = metadata(400, name: "Browser", path: "/Applications/Other/Browser.app/Contents/MacOS/Browser")
        let result = ProcessAppResolver.resolve(process, applications: [browser, otherBrowser])
        XCTAssertEqual(result.identity, .application(path: "/Applications/Other/Browser.app"))
    }

    func testGPUClientParserSumsQueuesAndKeepsUnknownCreator() {
        let properties: [String: Any] = [
            "IOUserClientCreator": "pid 100, Browser",
            "AppUsage": [
                ["accumulatedGPUTime": NSNumber(value: 1_000), "accumulatedGPUQueueCount": NSNumber(value: 1)],
                ["accumulatedGPUTime": NSNumber(value: 2_000), "accumulatedGPUQueueCount": NSNumber(value: 2)]
            ]
        ]
        let parsed = ApplicationGPUClientReader.parseClient(properties: properties, entryID: 7)
        XCTAssertEqual(parsed?.pid, 100)
        XCTAssertEqual(parsed?.gpuTime, 3_000)
        XCTAssertEqual(parsed?.queueCount, 3)
        XCTAssertEqual(parsed?.name, "Browser")

        let unknown = ApplicationGPUClientReader.parseClient(
            properties: ["AppUsage": [["accumulatedGPUTime": NSNumber(value: 500)]]],
            entryID: 8
        )
        XCTAssertNil(unknown?.pid)
        XCTAssertEqual(unknown?.gpuTime, 500)
    }

    func testUnattributableProcessKeepsItsOwnIdentity() {
        let process = metadata(300, name: "daemon", path: "/usr/libexec/daemon")
        let result = ProcessAppResolver.resolve(process, applications: [browser])
        XCTAssertEqual(result.identity, .process(ProcessIdentity(pid: 300, startedAt: 1)))
        XCTAssertEqual(result.name, "daemon")
        XCTAssertFalse(result.isApplication)
    }
}
