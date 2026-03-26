import Foundation

class AppState {

    static let shared = AppState()

    private let networkMonitor = NetworkMonitor()
    private let connectivityChecker = ConnectivityChecker()
    private let speedMonitor = NetworkSpeedMonitor()

    private var refreshTimer: Timer?
    private var debounceTimer: Timer?

    enum ConnectionStatus {
        case connected
        case blocked
        case noNetwork
    }

    var statusUpdateHandler: ((ConnectionStatus) -> Void)?
    var speedSnapshotHandler: ((NetworkSpeedMonitor.Snapshot) -> Void)?

    var refreshInterval: TimeInterval {
        let saved = UserDefaults.standard.double(for: .refreshInterval)
        return saved == 0 ? 30 : saved
    }

    // MARK: - Public Start

    func start() {

        // Listen for network interface changes (WiFi off, Ethernet unplugged)
        networkMonitor.pathChangedHandler = { [weak self] in
            self?.debouncedImmediateCheck()
        }

        networkMonitor.startMonitoring()

        let speedInterval = UserDefaults.standard.double(for: .speedTestInterval)
        speedMonitor.snapshotHandler = { [weak self] snapshot in
            self?.speedSnapshotHandler?(snapshot)
        }
        speedMonitor.start(interval: speedInterval == 0 ? 300 : speedInterval)

        startTimer()

        // Immediate outbound attempt on startup
        checkConnection()
    }

    // MARK: - On-demand refresh (e.g. user clicked a speed row)

    func forceRefreshSpeed() {
        checkConnection()
        speedMonitor.runNow()
    }

    // MARK: - Restart (when settings change)

    func restart() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let speedInterval = UserDefaults.standard.double(for: .speedTestInterval)
        speedMonitor.start(interval: speedInterval == 0 ? 300 : speedInterval)
        startTimer()
        checkConnection()
    }

    // MARK: - Timer

    private func startTimer() {

        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkConnection()
        }
    }

    // MARK: - Debounce for rapid network changes

    private func debouncedImmediateCheck() {

        debounceTimer?.invalidate()

        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: false
        ) { [weak self] _ in
            self?.checkConnection()
        }
    }

    // MARK: - Core Logic

    private func checkConnection() {

        if !networkMonitor.isConnected {
            statusUpdateHandler?(.noNetwork)
            return
        }

        // Attempt outbound request
        connectivityChecker.checkOutboundConnection { [weak self] reachable, latencyMs in

            DispatchQueue.main.async {
                self?.statusUpdateHandler?(reachable ? .connected : .blocked)
                if let ms = latencyMs {
                    self?.speedMonitor.updatePing(ms)
                }
            }
        }
    }
}
