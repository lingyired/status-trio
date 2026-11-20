import Combine
import XCTest
@testable import StatusTrioCore

@MainActor
final class LocalIconPluginTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-20T10:00:00Z")!

    // MARK: - Manifest

    func testManifestValidationAcceptsTheDocumentedSchema() throws {
        let manifest = try LocalIconPluginManifestLoader.load(directory: try writePackage(
            manifest: Self.manifestJSON(pluginID: "com.example.latency"),
            data: Self.dataJSON(observedAt: "2026-11-20T09:59:55Z")
        ))
        XCTAssertEqual(manifest.pluginID, "com.example.latency")
        XCTAssertEqual(manifest.presentations.first?.slot, .center)
        XCTAssertEqual(manifest.presentations.first?.kind, .text)
    }

    func testManifestRejectsBuiltinPrefixInvalidIDsAndSlotKindMismatches() throws {
        let builtin = try writePackage(manifest: Self.manifestJSON(pluginID: "builtin.mine"))
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: builtin)) {
            XCTAssertEqual($0 as? LocalIconPluginManifestError, .builtinPrefix)
        }

        let badID = try writePackage(manifest: Self.manifestJSON(pluginID: "has space"))
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: badID)) {
            XCTAssertEqual($0 as? LocalIconPluginManifestError, .invalidPluginID)
        }

        let wrongKind = try writePackage(manifest: """
        {"schemaVersion":1,"pluginID":"com.example.bad","title":"Bad",
         "presentations":[{"id":"text","slot":"outerRing","kind":"text"}]}
        """)
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: wrongKind)) {
            XCTAssertEqual($0 as? LocalIconPluginManifestError, .invalidPresentation("text"))
        }
    }

    func testManifestRejectsDuplicatePresentationsAndTooManyItems() throws {
        let duplicate = try writePackage(manifest: """
        {"schemaVersion":1,"pluginID":"com.example.dupe","title":"Dupe",
         "presentations":[{"id":"a","slot":"center","kind":"text"},
                          {"id":"a","slot":"footer","kind":"fraction"}]}
        """)
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: duplicate)) {
            XCTAssertEqual($0 as? LocalIconPluginManifestError, .duplicatePresentation("a"))
        }

        let many = (0...16).map { #"{"id":"p\#($0)","slot":"center","kind":"text"}"# }
            .joined(separator: ",")
        let tooMany = try writePackage(manifest: """
        {"schemaVersion":1,"pluginID":"com.example.many","title":"Many","presentations":[\(many)]}
        """)
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: tooMany)) {
            XCTAssertEqual($0 as? LocalIconPluginManifestError, .tooManyPresentations)
        }
    }

    func testFileReaderRejectsSymlinksOversizedAndNonRegularFiles() throws {
        let directory = try makeDirectory()
        let outside = try makeDirectory().appendingPathComponent("outside.json")
        try Data("{}".utf8).write(to: outside)
        let link = directory.appendingPathComponent("manifest.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: directory))

        try FileManager.default.removeItem(at: link)
        try Data(repeating: 0x20, count: LocalIconPluginManifest.maximumFileBytes + 1).write(to: link)
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: directory)) {
            XCTAssertEqual($0 as? LocalIconPluginManifestError, .tooLarge)
        }

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: false)
        XCTAssertThrowsError(try LocalIconPluginManifestLoader.load(directory: directory))
    }

    // MARK: - Catalog

    func testCatalogRejectsDuplicatePluginIDsAcrossEnabledDirectories() async throws {
        let first = try writePackage(manifest: Self.manifestJSON(pluginID: "com.example.dupe"))
        let second = try writePackage(manifest: Self.manifestJSON(pluginID: "com.example.dupe"))
        let catalog = await LocalIconPluginCatalog.load(directories: [first, second])
        XCTAssertTrue(catalog.packages.isEmpty)
        XCTAssertEqual(
            Set(catalog.rejections.map(\.directory)),
            [first, second],
            "every duplicate directory must stay identifiable so the management page can remove it"
        )
        XCTAssertTrue(catalog.rejections.contains(
            .duplicatePluginID("com.example.dupe", first)))
        XCTAssertTrue(catalog.rejections.contains(
            .duplicatePluginID("com.example.dupe", second)))
    }

    func testManagementListKeepsInvalidAndDuplicateDirectoriesRemovable() async throws {
        let valid = try writePackage(manifest: Self.manifestJSON(pluginID: "com.example.valid"))
        let invalid = try writePackage(manifest: "{ not json")
        let duplicateA = try writePackage(manifest: Self.manifestJSON(pluginID: "com.example.dupe"))
        let duplicateB = try writePackage(manifest: Self.manifestJSON(pluginID: "com.example.dupe"))
        let all = [valid, invalid, duplicateA, duplicateB]
        let catalog = await LocalIconPluginCatalog.load(directories: all)

        let rows = LocalIconPluginManageableDirectories.build(
            enabledPaths: all.map(\.path), catalog: catalog)
        XCTAssertEqual(Set(rows.map(\.directory)), Set(all))
        XCTAssertEqual(rows.first { $0.directory == valid }?.pluginID, "com.example.valid")
        XCTAssertNil(rows.first { $0.directory == invalid }?.pluginID)
        XCTAssertNil(rows.first { $0.directory == duplicateA }?.pluginID)
        XCTAssertNil(rows.first { $0.directory == duplicateB }?.pluginID)

        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        for url in all { store.addLocalIconPluginDirectory(url) }
        for row in rows { store.removeLocalIconPluginDirectory(row.directory) }
        XCTAssertTrue(store.localIconPluginDirectories.isEmpty,
                      "an invalid or duplicate package must not be stuck in preferences")
    }

    func testThreeSlotManifestOffersOneOptionPerSlot() async throws {
        let directory = try writePackage(manifest: """
        {"schemaVersion":1,"pluginID":"com.example.multi","title":"Multi",
         "presentations":[
          {"id":"ring","slot":"outerRing","kind":"fraction"},
          {"id":"readout","slot":"center","kind":"text"},
          {"id":"footer","slot":"footer","kind":"fraction"}]}
        """)
        let catalog = await LocalIconPluginCatalog.load(directories: [directory])
        XCTAssertEqual(catalog.packages.count, 1)
        XCTAssertEqual(LocalIconPluginSlotCatalog.options(for: .outerRing, in: catalog).map(\.binding.presentationID), ["ring"])
        XCTAssertEqual(LocalIconPluginSlotCatalog.options(for: .center, in: catalog).map(\.binding.presentationID), ["readout"])
        XCTAssertEqual(LocalIconPluginSlotCatalog.options(for: .footer, in: catalog).map(\.binding.presentationID), ["footer"])
    }

    // MARK: - Directory access

    func testSandboxedBuildHidesPackagesAndResolvesNoBarePaths() {
        let sandbox = [LocalIconPluginAccess.sandboxEnvironmentKey: "com.example.app"]
        XCTAssertFalse(LocalIconPluginAccess.entryIsAvailable(environment: sandbox))
        XCTAssertTrue(
            LocalIconPluginAccess.resolvedDirectories(
                paths: ["/tmp/authorized", "/tmp/other"], environment: sandbox
            ).isEmpty,
            "a sandboxed build must not fall back to persisted bare paths"
        )

        XCTAssertTrue(LocalIconPluginAccess.entryIsAvailable(environment: [:]))
        XCTAssertEqual(
            LocalIconPluginAccess.resolvedDirectories(paths: ["/tmp/authorized"], environment: [:])
                .map(\.path),
            ["/tmp/authorized"]
        )
    }

    func testDirectBuildAddsAndRemovesPackageDirectoriesWithoutBookmarks() throws {
        let defaults = try makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let directory = try makeDirectory()

        XCTAssertTrue(store.isLocalIconPluginEntryAvailable)
        XCTAssertTrue(store.addLocalIconPluginDirectory(directory))
        XCTAssertTrue(store.addLocalIconPluginDirectory(directory), "adding twice is a no-op")
        XCTAssertEqual(store.localIconPluginDirectories, [directory.path])
        XCTAssertEqual(store.resolvedLocalIconPluginDirectories().map(\.path), [directory.path])

        store.removeLocalIconPluginDirectory(directory)
        XCTAssertTrue(store.localIconPluginDirectories.isEmpty)
        XCTAssertTrue(store.resolvedLocalIconPluginDirectories().isEmpty)
    }

    func testRuntimeStartsOneFeedForTwoPresentationsAndRestartsAfterStop() async throws {
        let directory = try writePackage(
            manifest: """
            {"schemaVersion":1,"pluginID":"com.example.multi","title":"Multi",
             "presentations":[
              {"id":"a","slot":"center","kind":"text"},
              {"id":"b","slot":"center","kind":"text"}]}
            """,
            data: """
            {"schemaVersion":1,"observedAt":"2026-11-20T09:59:55Z",
             "values":{"a":"1","b":"2"}}
            """
        )
        let runtime = LocalIconPluginRuntime(
            directories: { [directory] },
            fileWatching: false
        )
        runtime.start()
        await runtime.awaitInitialCatalog()
        let bindings: Set<IconContentBinding> = [
            .init(pluginID: "com.example.multi", presentationID: "a"),
            .init(pluginID: "com.example.multi", presentationID: "b")
        ]
        runtime.updateDemand(bindings)
        XCTAssertTrue(runtime.isFeedRunning(pluginID: "com.example.multi"))
        XCTAssertEqual(runtime.runningFeedCount, 1,
                       "two presentations of one package share a single file feed")

        runtime.stop()
        XCTAssertEqual(runtime.runningFeedCount, 0)
        runtime.start()
        await runtime.awaitInitialCatalog()
        XCTAssertEqual(runtime.runningFeedCount, 1, "demand survives a runtime stop/start")
        XCTAssertTrue(runtime.isFeedRunning(pluginID: "com.example.multi"))
        runtime.stop()
    }

    // MARK: - Data

    func testTextReadingRejectsControlCharactersAndOverlongText() throws {
        let manifest = try Self.manifest()
        let control = Self.dataJSON(observedAt: "2026-11-20T09:59:55Z", text: "42\\nms")
        XCTAssertThrowsError(try LocalIconPluginDataReader.decode(
            data: Data(control.utf8), manifest: manifest, now: now, lastAccepted: nil)) {
            XCTAssertEqual($0 as? LocalIconPluginDataError, .invalidValue("value"))
        }

        let long = Self.dataJSON(observedAt: "2026-11-20T09:59:55Z", text: String(repeating: "x", count: 17))
        XCTAssertThrowsError(try LocalIconPluginDataReader.decode(
            data: Data(long.utf8), manifest: manifest, now: now, lastAccepted: nil))
    }

    func testFractionReadingRejectsOutOfRangeAndNonFiniteValues() throws {
        let manifest = try LocalIconPluginManifest(
            schemaVersion: 1, pluginID: "com.example.load", title: "Load",
            presentations: [.init(id: "value", slot: .outerRing, kind: .fraction)])
        for value in ["1.5", "-0.1"] {
            let data = """
            {"schemaVersion":1,"observedAt":"2026-11-20T09:59:55Z","values":{"value":\(value)}}
            """
            XCTAssertThrowsError(try LocalIconPluginDataReader.decode(
                data: Data(data.utf8), manifest: manifest, now: now, lastAccepted: nil))
        }
    }

    func testReadingRejectsFutureStaleAndOlderThanCurrent() throws {
        let manifest = try Self.manifest()
        let future = Self.dataJSON(observedAt: "2026-11-20T10:00:03Z")
        XCTAssertThrowsError(try LocalIconPluginDataReader.decode(
            data: Data(future.utf8), manifest: manifest, now: now, lastAccepted: nil)) {
            XCTAssertEqual($0 as? LocalIconPluginDataError, .futureObservedAt)
        }

        let stale = Self.dataJSON(observedAt: "2026-11-20T09:59:40Z")
        XCTAssertThrowsError(try LocalIconPluginDataReader.decode(
            data: Data(stale.utf8), manifest: manifest, now: now, lastAccepted: nil)) {
            XCTAssertEqual($0 as? LocalIconPluginDataError, .staleReading)
        }

        let older = Self.dataJSON(observedAt: "2026-11-20T09:59:54Z")
        let newer = ISO8601DateFormatter().date(from: "2026-11-20T09:59:58Z")!
        XCTAssertThrowsError(try LocalIconPluginDataReader.decode(
            data: Data(older.utf8), manifest: manifest, now: now, lastAccepted: newer)) {
            XCTAssertEqual($0 as? LocalIconPluginDataError, .olderThanCurrent)
        }
    }

    // MARK: - Feed

    func testFeedReturnsNilAfterDeletionAndExpiry() async throws {
        let directory = try writePackage(
            manifest: Self.manifestJSON(pluginID: "com.example.latency"),
            data: Self.dataJSON(observedAt: "2026-11-20T09:59:55Z")
        )
        let expiry = ManualLocalIconExpiryScheduler()
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { [now] in now },
            expiry: expiry,
            fileWatching: false
        )
        feed.start(reloadImmediately: false)
        await feed.reload()
        XCTAssertEqual(feed.reading?.values["value"], .text("42 ms"))

        try FileManager.default.removeItem(at: directory.appendingPathComponent("data.json"))
        await feed.reload()
        XCTAssertNil(feed.reading, "a deleted data file falls back immediately")

        // A later valid reading schedules the 15 s deadline; firing it clears
        // the value even when the script stops writing.
        try Data(Self.dataJSON(observedAt: "2026-11-20T09:59:58Z").utf8)
            .write(to: directory.appendingPathComponent("data.json"))
        await feed.reload()
        XCTAssertNotNil(feed.reading)
        expiry.fire()
        XCTAssertNil(feed.reading)
        feed.stop()
    }

    func testFeedIgnoresAnOlderReadingThatArrivesAfterANewerOne() async throws {
        let directory = try writePackage(
            manifest: Self.manifestJSON(pluginID: "com.example.latency"),
            data: Self.dataJSON(observedAt: "2026-11-20T09:59:58Z")
        )
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { [now] in now },
            expiry: ManualLocalIconExpiryScheduler(),
            fileWatching: false
        )
        feed.start(reloadImmediately: false)
        await feed.reload()
        let newest = feed.reading?.observedAt

        try Data(Self.dataJSON(observedAt: "2026-11-20T09:59:55Z").utf8)
            .write(to: directory.appendingPathComponent("data.json"))
        await feed.reload()
        XCTAssertEqual(feed.reading?.observedAt, newest, "an older read must not overwrite the current value")
        feed.stop()
    }

    // MARK: - Plugin

    func testLocalPluginRendersTextAndFractionBindings() throws {
        let store = LocalIconPluginValueStore()
        let manifest = try Self.manifest()
        let plugin = LocalIconPlugin(manifest: manifest, store: store)
        store.update(pluginID: manifest.pluginID, reading: LocalIconPluginReading(
            schemaVersion: 1,
            observedAt: now,
            values: ["value": .text("42 ms")]
        ))
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(primary: .init(pluginID: manifest.pluginID, presentationID: "value")),
            footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let registry = try IconContentPluginRegistry(
            plugins: BuiltinIconPlugins.makePlugins() + [plugin])
        let output = IconCompositionResolver.resolve(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
                sources: .empty),
            configuration: .classic,
            bindings: bindings,
            registry: registry
        )
        XCTAssertEqual(output.scene.center, .text(IconTextState(
            text: "42 ms", color: .primary, scale: IconPresentationConfiguration.standard.connection.wifiScale)))
        XCTAssertEqual(output.trace.center.binding?.pluginID, manifest.pluginID)
    }

    func testLatencyReadingUpdatesThenFallsBackWhenWritingStops() throws {
        let store = LocalIconPluginValueStore()
        let manifest = try Self.manifest()
        let plugin = LocalIconPlugin(manifest: manifest, store: store)
        let bindings = IconSlotBindingsV1(
            schemaVersion: 1,
            outerRing: .init(primary: .init(pluginID: "builtin.system-battery", presentationID: "ring")),
            center: .init(
                primary: .init(pluginID: manifest.pluginID, presentationID: "value"),
                fallback: .init(pluginID: "builtin.network", presentationID: "center")),
            footer: .init(primary: .init(pluginID: "builtin.system-volume", presentationID: "footer"))
        )
        let registry = try IconContentPluginRegistry(
            plugins: BuiltinIconPlugins.makePlugins() + [plugin])
        let inputs = IconResolutionInputs(
            system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
            sources: .empty)

        func resolve() -> IconResolutionOutput {
            IconCompositionResolver.resolve(
                inputs: inputs, configuration: .classic, now: now,
                bindings: bindings, registry: registry)
        }

        store.update(pluginID: manifest.pluginID, reading: LocalIconPluginReading(
            schemaVersion: 1, observedAt: now, values: ["value": .text("42 ms")]))
        XCTAssertEqual(resolve().scene.center, .text(IconTextState(text: "42 ms", color: .primary, scale: 1)))

        store.update(pluginID: manifest.pluginID, reading: LocalIconPluginReading(
            schemaVersion: 1, observedAt: now.addingTimeInterval(1), values: ["value": .text("57 ms")]))
        XCTAssertEqual(resolve().scene.center, .text(IconTextState(text: "57 ms", color: .primary, scale: 1)))

        // The producer stops writing: the saved reading expires and the fallback
        // network source draws, without the package being removed.
        store.update(pluginID: manifest.pluginID, reading: LocalIconPluginReading(
            schemaVersion: 1, observedAt: now.addingTimeInterval(-16), values: ["value": .text("57 ms")]))
        XCTAssertEqual(resolve().trace.center.role, .fallback)
        XCTAssertEqual(resolve().trace.center.selectedSourceID, CenterSource.network.rawValue)

        // The script starts writing again: no package removal/re-enable is
        // needed, the saved primary binding recovers on its own.
        store.update(pluginID: manifest.pluginID, reading: LocalIconPluginReading(
            schemaVersion: 1, observedAt: now.addingTimeInterval(2), values: ["value": .text("57 ms")]))
        XCTAssertEqual(resolve().trace.center.role, .primary)
        XCTAssertEqual(resolve().scene.center, .text(IconTextState(text: "57 ms", color: .primary, scale: 1)))
    }

    func testLocalPluginIsUnavailableAfterItsReadingExpires() throws {
        let store = LocalIconPluginValueStore()
        let manifest = try Self.manifest()
        store.update(pluginID: manifest.pluginID, reading: LocalIconPluginReading(
            schemaVersion: 1,
            observedAt: now.addingTimeInterval(-16),
            values: ["value": .text("old")]
        ))
        let plugin = LocalIconPlugin(manifest: manifest, store: store)
        let context = IconContentContext(
            inputs: IconResolutionInputs(
                system: IconPresentationInputs(snapshot: .placeholder, audioIcon: nil),
                sources: .empty),
            configuration: .classic,
            legacy: .standard,
            now: now
        )
        XCTAssertEqual(plugin.resolve(presentationID: "value", context: context),
                       .unavailable(.temporarilyStale))
    }

    func testRuntimePublishesEnabledPackagesAndStartsFeedsOnlyWhenDemanded() async throws {
        let directory = try writePackage(
            manifest: Self.manifestJSON(pluginID: "com.example.latency"),
            data: Self.dataJSON(observedAt: "2026-11-20T09:59:58Z")
        )
        let runtime = LocalIconPluginRuntime(directories: { [directory] }, fileWatching: false)
        runtime.start()
        await runtime.awaitInitialCatalog()
        XCTAssertEqual(runtime.catalog.packages.map(\.pluginID), ["com.example.latency"])

        let binding = IconContentBinding(pluginID: "com.example.latency", presentationID: "value")
        XCTAssertNotNil(runtime.registry.presentation(for: binding))
        XCTAssertFalse(runtime.isFeedRunning(pluginID: "com.example.latency"))

        runtime.updateDemand([binding])
        XCTAssertTrue(runtime.isFeedRunning(pluginID: "com.example.latency"))
        runtime.updateDemand([])
        XCTAssertFalse(runtime.isFeedRunning(pluginID: "com.example.latency"))
        runtime.stop()
    }

    // MARK: - Reader and reload limits

    func testFileReaderRejectsFIFOWithoutBlocking() throws {
        let directory = try makeDirectory()
        let fifo = directory.appendingPathComponent("data.json")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)

        let result = LockedBox<LocalIconPluginManifestError?>(nil)
        let returned = expectation(description: "FIFO read returned")
        Task.detached {
            do {
                _ = try LocalIconFileReader.readRegularFile(
                    at: "data.json", inDirectory: directory, maximumBytes: 1024)
            } catch {
                result.set(error as? LocalIconPluginManifestError)
            }
            returned.fulfill()
        }
        wait(for: [returned], timeout: 2)
        XCTAssertEqual(result.value, .notRegularFile,
                       "a non-regular fixed file must be rejected, not block open(2)")
    }

    func testReloadKeepsOneReadInFlightAndCoalescesABurst() async throws {
        let directory = try makeDirectory()
        let reading = LocalIconPluginReading(
            schemaVersion: 1, observedAt: now, values: ["value": .text("42 ms")])
        let probe = BlockingFeedLoadProbe(blockedCall: 1, reading: reading)
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { [now] in now },
            expiry: ManualLocalIconExpiryScheduler(),
            fileWatching: false,
            loader: probe.load
        )
        feed.start(reloadImmediately: false)

        let first = Task { await feed.reload() }
        await fulfillment(of: [probe.firstReadStarted], timeout: 2)
        let pendingOne = Task { await feed.reload() }
        let pendingTwo = Task { await feed.reload() }
        for _ in 0..<200 where !feed.hasPendingReload {
            await Task.yield()
        }
        XCTAssertTrue(feed.hasPendingReload, "a burst must collapse into one pending read")

        probe.releaseBlockedCall()
        await first.value
        await pendingOne.value
        await pendingTwo.value

        XCTAssertEqual(probe.callCount, 2,
                       "one read in flight plus at most one coalesced follow-up")
        XCTAssertEqual(probe.maximumConcurrentReads, 1)
        XCTAssertEqual(feed.reading, reading)
        feed.stop()
    }

    func testStopDropsAnInFlightRead() async throws {
        let directory = try makeDirectory()
        let probe = BlockingFeedLoadProbe(
            blockedCall: 1,
            reading: LocalIconPluginReading(
                schemaVersion: 1, observedAt: now, values: ["value": .text("old")])
        )
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { [now] in now },
            expiry: ManualLocalIconExpiryScheduler(),
            fileWatching: false,
            loader: probe.load
        )
        feed.start(reloadImmediately: false)

        let task = Task { await feed.reload() }
        await fulfillment(of: [probe.firstReadStarted], timeout: 2)
        feed.stop()
        probe.releaseBlockedCall()
        await task.value
        XCTAssertNil(feed.reading, "a result from the stopped generation must never be written back")
    }

    func testExpiredInFlightReadIsNotWrittenBack() async throws {
        let directory = try makeDirectory()
        let clock = MutableIconPluginClock(now)
        let reading = LocalIconPluginReading(
            schemaVersion: 1, observedAt: now, values: ["value": .text("42 ms")])
        // The first read seeds a value; the second read is held past its deadline.
        let probe = BlockingFeedLoadProbe(blockedCall: 2, reading: reading)
        let expiry = ManualLocalIconExpiryScheduler()
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { clock.value },
            expiry: expiry,
            fileWatching: false,
            loader: probe.load
        )
        feed.start(reloadImmediately: false)
        await feed.reload()
        XCTAssertEqual(feed.reading, reading)

        let task = Task { await feed.reload() }
        await fulfillment(of: [probe.firstReadStarted], timeout: 2)
        clock.advance(by: LocalIconPluginReading.maximumLifetime + 5)
        expiry.fire()
        XCTAssertNil(feed.reading)
        probe.releaseBlockedCall()
        await task.value

        XCTAssertNil(feed.reading,
                     "an expired read must not resurrect a value after the deadline")
        feed.stop()
    }

    func testPreviousExpiryGenerationCannotClearANewerReading() async throws {
        let directory = try writePackage(
            manifest: Self.manifestJSON(pluginID: "com.example.latency"),
            data: Self.dataJSON(observedAt: "2026-11-20T09:59:55Z")
        )
        let expiry = RecordingExpiryScheduler()
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { [now] in now },
            expiry: expiry,
            fileWatching: false
        )
        feed.start(reloadImmediately: false)
        await feed.reload()
        XCTAssertEqual(feed.reading?.values["value"], .text("42 ms"))

        try Data(Self.dataJSON(observedAt: "2026-11-20T09:59:58Z", text: "57 ms").utf8)
            .write(to: directory.appendingPathComponent("data.json"))
        await feed.reload()
        XCTAssertEqual(feed.reading?.values["value"], .text("57 ms"))

        // Fire the expiry callback that belonged to the first reading. Its
        // generation is stale and must not clear the newer value.
        expiry.fireOldest()
        XCTAssertEqual(feed.reading?.values["value"], .text("57 ms"))
        feed.stop()
    }

    func testDirectoryWatcherPublishesAnAtomicReplacement() async throws {
        let directory = try writePackage(
            manifest: Self.manifestJSON(pluginID: "com.example.latency"),
            data: Self.dataJSON(observedAt: "2026-11-20T09:59:55Z")
        )
        let feed = LocalIconPluginFeed(
            directory: directory,
            manifest: try Self.manifest(),
            now: { [now] in now },
            expiry: ManualLocalIconExpiryScheduler(),
            fileWatching: true
        )
        feed.start()
        await waitUntil(timeout: 3) { feed.reading?.values["value"] == .text("42 ms") }

        // Atomic replacement is what the documented producer pattern uses.
        try Data(Self.dataJSON(observedAt: "2026-11-20T09:59:58Z", text: "57 ms").utf8)
            .write(to: directory.appendingPathComponent("data.json"), options: .atomic)
        await waitUntil(timeout: 3) { feed.reading?.values["value"] == .text("57 ms") }
        feed.stop()
    }

    // MARK: - Fixtures

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("condition was not met within \(timeout) seconds")
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "StatusTrioCoreTests.LocalIconPlugin.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeDirectory() throws -> URL {        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalIconPluginTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    @discardableResult
    private func writePackage(manifest: String, data: String? = nil) throws -> URL {
        let directory = try makeDirectory()
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("manifest.json"))
        if let data {
            try Data(data.utf8).write(to: directory.appendingPathComponent("data.json"))
        }
        return directory
    }

    private static func manifest() throws -> LocalIconPluginManifest {
        try LocalIconPluginManifest(
            schemaVersion: 1, pluginID: "com.example.latency", title: "Latency",
            presentations: [.init(id: "value", slot: .center, kind: .text)])
    }

    private static func manifestJSON(pluginID: String) -> String {
        """
        {"schemaVersion":1,"pluginID":"\(pluginID)","title":"Latency",
         "presentations":[{"id":"value","slot":"center","kind":"text"}]}
        """
    }

    private static func dataJSON(observedAt: String, text: String = "42 ms") -> String {
        """
        {"schemaVersion":1,"observedAt":"\(observedAt)","values":{"value":"\(text)"}}
        """
    }
}

@MainActor
private final class ManualLocalIconExpiryScheduler: LocalIconPluginExpiryScheduling {
    private var actions: [@MainActor () -> Void] = []

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        actions.append(action)
    }

    func cancel() {
        actions.removeAll()
    }

    func fire() {
        let pending = actions
        actions.removeAll()
        for action in pending { action() }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

private final class BlockingFeedLoadProbe: @unchecked Sendable {
    let firstReadStarted = XCTestExpectation(description: "feed read started")
    private let blockedCall: Int
    private let reading: LocalIconPluginReading
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0
    private var concurrent = 0
    private var maxConcurrent = 0

    init(blockedCall: Int, reading: LocalIconPluginReading) {
        self.blockedCall = blockedCall
        self.reading = reading
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    var maximumConcurrentReads: Int {
        lock.lock()
        defer { lock.unlock() }
        return maxConcurrent
    }

    func releaseBlockedCall() {
        release.signal()
    }

    func load(
        _ directory: URL,
        _ manifest: LocalIconPluginManifest,
        _ now: Date,
        _ lastAccepted: Date?
    ) -> LocalIconPluginFeedLoadResult {
        lock.lock()
        calls += 1
        let call = calls
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        lock.unlock()

        if call == blockedCall {
            firstReadStarted.fulfill()
            release.wait()
        }

        lock.lock()
        concurrent -= 1
        lock.unlock()
        return .reading(reading)
    }
}

private final class MutableIconPluginClock {
    private(set) var value: Date

    init(_ value: Date) { self.value = value }

    func advance(by interval: TimeInterval) {
        value = value.addingTimeInterval(interval)
    }
}

@MainActor
private final class RecordingExpiryScheduler: LocalIconPluginExpiryScheduling {
    private var actions: [@MainActor () -> Void] = []

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        actions.append(action)
    }

    func cancel() {
        // Keep the historical callbacks so a test can fire an old generation.
    }

    func fireOldest() {
        guard !actions.isEmpty else { return }
        actions.removeFirst()()
    }
}
