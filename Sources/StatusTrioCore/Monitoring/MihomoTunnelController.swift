import Foundation

/// Keeps the VPN row's Mihomo attribution fresh while the row is visible.
/// Read-only and demand-driven: it never writes the TUN or Clash's settings.
@MainActor
final class MihomoTunnelController: ObservableObject {
    @Published private(set) var info: MihomoTunnelInfo?
    var onUpdate: (@MainActor (MihomoTunnelInfo?) -> Void)?

    private let client: any MihomoTunnelReading
    private let observer: any NetworkChangeObserving
    private let queue = DispatchQueue(label: "StatusTrio.MihomoTunnel")
    private var active = false
    private var generation = 0
    private var task: Task<Void, Never>?

    init(
        client: any MihomoTunnelReading = SystemMihomoTunnelClient(),
        observer: any NetworkChangeObserving = SystemNetworkChangeObserver()
    ) {
        self.client = client
        self.observer = observer
    }

    func activate() {
        guard !active else { return }
        active = true
        generation += 1
        let expected = generation
        observer.start(queue: queue) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == expected else { return }
                self.refresh()
            }
        }
        refresh()
    }

    func deactivate() {
        guard active else { return }
        active = false
        generation += 1
        task?.cancel()
        task = nil
        observer.cancel()
        publish(nil)
    }

    func refresh() {
        guard active else { return }
        let expected = generation
        task?.cancel()
        task = Task { [weak self, client] in
            let next = await client.read()
            guard let self, !Task.isCancelled, self.active, self.generation == expected else { return }
            self.publish(next)
        }
    }

    private func publish(_ next: MihomoTunnelInfo?) {
        guard info != next else { return }
        info = next
        onUpdate?(next)
    }
}
