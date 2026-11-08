import Foundation

final class AppState {

    static let shared = AppState()

    private let networkMonitor = NetworkMonitor()
    private let connectivityChecker = ConnectivityChecker()
    private let speedMonitor = NetworkSpeedMonitor()

    private var refreshTimer: Timer?
    private var debounceTimer: Timer?
    private var lastWifiSSID: String?
    private var dnsLookupInFlight = false

    enum ConnectionStatus {
        case connected
        case blocked
        case noNetwork
    }

    private(set) var isVPNActive: Bool = false

    /// Called when the connection status changes. Receives the new status and the
    /// current network addresses snapshot so callers don't need to re-query.
    var statusUpdateHandler: ((ConnectionStatus, IPAddressProvider.Addresses) -> Void)?
    /// Called when the VPN state changes. Receives the current addresses snapshot.
    var vpnStatusChangedHandler: ((IPAddressProvider.Addresses) -> Void)?
    /// Called on every connectivity check cycle. Receives the current addresses snapshot.
    var networkAddressesChangedHandler: ((IPAddressProvider.Addresses) -> Void)?
    /// Called after each probe cycle with per-target results and captive-portal detection.
    var probeResultHandler: ((ProbeResult) -> Void)?
    /// Called with the DNS lookup time in ms, or nil if the resolver didn't answer.
    var dnsLookupHandler: ((Double?) -> Void)?
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

        // Call current() once; pass the snapshot to all handlers so they don't re-query.
        let addresses = IPAddressProvider.current()

        let ssidChanged = addresses.wifiName != lastWifiSSID
        lastWifiSSID = addresses.wifiName

        if ssidChanged {
            speedResetHandler?()
        }

        let previousVPNActive = isVPNActive
        isVPNActive = addresses.isVPNActive
        if isVPNActive != previousVPNActive {
            vpnStatusChangedHandler?(addresses)
        }

        networkAddressesChangedHandler?(addresses)

        if !networkMonitor.isConnected {
            statusUpdateHandler?(.noNetwork, addresses)
            return
        }

        measureDNSLookup()

        // Attempt outbound requests (delivered on the main thread)
        connectivityChecker.checkOutboundConnection { [weak self] result in
            self?.probeResultHandler?(result)
            self?.statusUpdateHandler?(result.reachable ? .connected : .blocked, addresses)
            if let ms = result.latencyMs {
                self?.speedMonitor.updatePing(ms)
            }
            if ssidChanged && result.reachable {
                self?.speedMonitor.runNow()
            }
        }
    }

    /// Skipped while a previous lookup is still pending, so a dead resolver can't pile up threads.
    private func measureDNSLookup() {
        guard !dnsLookupInFlight else { return }
        dnsLookupInFlight = true
        ConnectivityChecker.measureDNSLookup { [weak self] ms in
            DispatchQueue.main.async {
                self?.dnsLookupInFlight = false
                self?.dnsLookupHandler?(ms)
            }
        }
    }
}
