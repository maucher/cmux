import Foundation
@preconcurrency import Network

/// Reports when the Mac's network becomes usable again, or switches networks
/// while usable, so remote sessions can be restored without waiting for wake.
@MainActor
final class RemoteSessionNetworkPathMonitor {
    struct Snapshot: Equatable {
        var isSatisfied: Bool
        var signature: String
    }

    /// The first observation is a baseline; afterwards a path that becomes
    /// satisfied, or changes interfaces/gateways while satisfied, is a restore.
    nonisolated static func shouldReportRestored(previous: Snapshot?, current: Snapshot) -> Bool {
        guard current.isSatisfied, let previous else { return false }
        return !previous.isSatisfied || previous.signature != current.signature
    }

    nonisolated static func snapshot(
        isSatisfied: Bool,
        interfaceNames: [String],
        gateways: [String]
    ) -> Snapshot {
        Snapshot(
            isSatisfied: isSatisfied,
            signature: (interfaceNames.sorted() + ["|"] + gateways.sorted()).joined(separator: ",")
        )
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cmux.remote-session-network-path")
    private var last: Snapshot?
    private let onRestored: @MainActor () -> Void

    private(set) var isSatisfied = true

    init(onRestored: @escaping @MainActor () -> Void) {
        self.onRestored = onRestored
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = Self.snapshot(
                isSatisfied: path.status == .satisfied,
                interfaceNames: path.availableInterfaces.map(\.name),
                gateways: path.gateways.map { String(describing: $0) }
            )
            Task { @MainActor [weak self] in
                self?.handle(snapshot)
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }

    private func handle(_ snapshot: Snapshot) {
        let restored = Self.shouldReportRestored(previous: last, current: snapshot)
        last = snapshot
        isSatisfied = snapshot.isSatisfied
        if restored { onRestored() }
    }
}
