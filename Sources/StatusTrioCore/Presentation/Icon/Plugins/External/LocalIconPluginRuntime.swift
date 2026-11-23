import Combine
import Foundation

/// Loads the user's enabled local packages and owns their feeds.
///
/// The catalog is metadata-only; a package's `data.json` is watched only while
/// one of its presentations is named by the resolved icon demand. Changing the
/// enabled directory list reloads the catalog, keeps the saved slot bindings
/// untouched, and re-publishes the registry so a returning package resolves
/// again.
@MainActor
final class LocalIconPluginRuntime {
    let changes = PassthroughSubject<Void, Never>()
    private let store = LocalIconPluginValueStore()
    private let directories: @MainActor () -> [URL]
    private let fileWatching: Bool
    private(set) var catalog = LocalIconPluginCatalog()
    private(set) var registry: IconContentPluginRegistry = BuiltinIconPlugins.makeRegistry()
    private var feeds: [String: LocalIconPluginFeed] = [:]
    private var feedCancellables = Set<AnyCancellable>()
    private var demand: Set<IconContentBinding> = []
    private var isStarted = false
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init(
        directories: @escaping @MainActor () -> [URL],
        fileWatching: Bool = true
    ) {
        self.directories = directories
        self.fileWatching = fileWatching
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reloadTask = Task { await reloadCatalog() }
    }

    /// Waits for the initial catalog load started by `start()`. Tests and
    /// lifecycle probes use this instead of starting a competing reload.
    func awaitInitialCatalog() async {
        await reloadTask?.value
    }

    func stop() {
        isStarted = false
        reloadTask?.cancel()
        reloadTask = nil
        for feed in feeds.values { feed.stop() }
        feeds.removeAll()
        feedCancellables.removeAll()
        store.clearAll()
    }

    /// Re-reads the enabled directories. Existing feeds are rebuilt so a package
    /// replaced on disk is never served from a stale manifest.
    func reloadCatalog() async {
        guard isStarted else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        let catalog = await LocalIconPluginCatalog.load(directories: directories())
        guard isStarted, generation == reloadGeneration else { return }
        self.catalog = catalog

        for feed in feeds.values { feed.stop() }
        feeds.removeAll()
        feedCancellables.removeAll()
        store.clearAll()

        var plugins = BuiltinIconPlugins.makePlugins()
        for package in catalog.packages {
            let feed = LocalIconPluginFeed(
                directory: package.directory,
                manifest: package.manifest,
                fileWatching: fileWatching
            )
            feeds[package.pluginID] = feed
            feed.$reading
                .sink { [weak self] reading in
                    guard let self else { return }
                    self.store.update(pluginID: package.pluginID, reading: reading)
                    self.changes.send(())
                }
                .store(in: &feedCancellables)
            plugins.append(LocalIconPlugin(manifest: package.manifest, store: store))
        }
        do {
            registry = try IconContentPluginRegistry(plugins: plugins)
        } catch {
            registry = BuiltinIconPlugins.makeRegistry()
        }
        applyDemandToFeeds()
        changes.send(())
    }

    /// Starts only the feeds named by the current slot demand. A primary external
    /// binding stays demanded even while its fallback draws, so it can recover.
    func updateDemand(_ bindings: Set<IconContentBinding>) {
        guard bindings != demand else { return }
        demand = bindings
        applyDemandToFeeds()
    }

    func isFeedRunning(pluginID: String) -> Bool {
        feeds[pluginID]?.isRunning == true
    }

    /// One feed exists per package, never per presentation; tests use this to
    /// prove that several presentations of one package share a watcher.
    var runningFeedCount: Int {
        feeds.values.filter(\.isRunning).count
    }

    private func applyDemandToFeeds() {
        let needed = Set(demand.map(\.pluginID))
        for (pluginID, feed) in feeds {
            if needed.contains(pluginID) {
                feed.start()
            } else {
                feed.stop()
                store.update(pluginID: pluginID, reading: nil)
            }
        }
    }
}
