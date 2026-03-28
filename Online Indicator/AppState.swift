import Foundation

class AppState {

    static let shared = AppState()

    private let networkMonitor = NetworkMonitor()
    private let connectivityChecker = ConnectivityChecker()
    private let speedMonitor = NetworkSpeedMonitor()

    private var refreshTimer: Timer?
    private var debounceTimer: Timer?
    private var lastWifiSSID: String?

    enum ConnectionStatus {
        case connected
        case blocked
        case noNetwork
    }

    private(set) var isVPNActive: Bool = false

    var statusUpdateHandler: ((ConnectionStatus) -> Void)?
    var vpnStatusChangedHandler: (() -> Void)?
    var speedSnapshotHandler: ((NetworkSpeedMonitor.Snapshot) -> Void)?
    var speedMeasuringChangedHandler: ((Bool) -> Void)?
    var speedResetHandler: (() -> Void)?

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

        speedMonitor.snapshotHandler = { [weak self] snapshot in
            self?.speedSnapshotHandler?(snapshot)
        }

        speedMonitor.measuringChangedHandler = { [weak self] measuring in
            self?.speedMeasuringChangedHandler?(measuring)
        }

        lastWifiSSID = IPAddressProvider.current().wifiName

        startTimer()

        // Immediate ping/connectivity check on startup
        checkConnection()

        // Short delay before speed test to avoid cold-start DNS/TCP/TLS overhead
        // skewing the first measurement lower than actual throughput.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.speedMonitor.runNow()
        }
    }

    // MARK: - Restart (when settings change)

    func restart() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        startTimer()
        checkConnection()
    }

    // MARK: - On-demand refresh (e.g. user clicked a speed row)

    func forceRefreshPing() {
        checkConnection()
    }

    func forceRefreshSpeed() {
        speedMonitor.runNow()
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

        let currentSSID = IPAddressProvider.current().wifiName
        let ssidChanged = currentSSID != lastWifiSSID
        lastWifiSSID = currentSSID

        if ssidChanged {
            speedResetHandler?()
        }

        let previousVPNActive = isVPNActive
        isVPNActive = IPAddressProvider.isVPNActive()
        if isVPNActive != previousVPNActive {
            vpnStatusChangedHandler?()
        }

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
                if ssidChanged && reachable {
                    self?.speedMonitor.runNow()
                }
            }
        }
    }
}
