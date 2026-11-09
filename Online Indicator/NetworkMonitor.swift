import Network

class NetworkMonitor {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")

    var pathChangedHandler: (() -> Void)?

    private(set) var isConnected: Bool = false
    /// Personal hotspot or Low Data Mode: the path where a 30 MB speed test is a real cost.
    private(set) var isMetered: Bool = false

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isMetered = path.isExpensive || path.isConstrained
                self?.pathChangedHandler?()
            }
        }

        // Not read from `currentPath` here: right after start() it still reports `unsatisfied`.
        // The first pathUpdateHandler call delivers the real initial state.
        monitor.start(queue: queue)
    }
}
